import 'dart:async';
import 'dart:typed_data';

import '../logger/airoc_data_logger.dart';
import '../models/ota_result.dart';
import '../models/ota_status.dart';
import 'airoc_ota_constants.dart';
import 'airoc_ota_protocol.dart';
import 'ota_file.dart';

// Convenience alias used throughout this file.
final _log = AirocDataLogger.instance;

/// BLE transport abstraction used by the OTA service.
abstract class AirocOtaTransport {
  Stream<List<int>> get notifications;

  Future<void> connect();

  Future<void> discover();

  Future<void> enableNotifications();

  Future<int> requestMtu(int desiredMtu);

  Future<void> write(List<int> data, {bool withoutResponse = false});

  Future<void> disconnect();
}

/// Executes an Infineon AIROC bootloader v1 OTA session.
class AirocOtaService {
  final AirocOtaTransport transport;
  final StreamController<OtaProgress> _progressController =
      StreamController<OtaProgress>.broadcast();

  StreamSubscription<List<int>>? _notificationSubscription;
  Completer<Uint8List>? _pendingResponse;
  bool _cancelRequested = false;
  int _bytesTransferred = 0;

  AirocOtaService({required this.transport});

  Stream<OtaProgress> get progressStream => _progressController.stream;

  void cancel() {
    _cancelRequested = true;
  }

  Future<OtaResult> performOta(
    OtaFile file, {
    void Function(OtaProgress progress)? onProgress,
    /// Optional compatibility override. Normally not needed.
    int? securityKeyOverride,
  }) async {
    final stopwatch = Stopwatch()..start();
    _cancelRequested = false;
    _bytesTransferred = 0;

    _log.i('OTA', '══════════════ OTA SESSION START ══════════════');
    _log.i('OTA', 'File     : ${file.fileName}  (${file.fileType.name})');
    _log.i('OTA', 'Rows     : ${file.rows.length}  totalBytes=${file.size}');
    _log.v('OTA', 'SiliconID: 0x${file.siliconId.toRadixString(16).padLeft(8, '0')}  rev=0x${file.siliconRev.toRadixString(16)}');
    _log.v('OTA', 'ProductID: 0x${file.productId.toRadixString(16).padLeft(8, '0')}  appId=${file.appId}');
    _log.v('OTA', 'Checksum : 0x${file.checksumType.toRadixString(16)}  appStart=0x${file.appStart.toRadixString(16)}  appSize=${file.appSize}');

    void emit(OtaProgress progress) {
      _log.v('OTA', 'STATE → ${progress.status.name}  "${progress.message}"');
      if (!_progressController.isClosed) {
        _progressController.add(progress);
      }
      onProgress?.call(progress);
    }

    try {
      emit(const OtaProgress(
        status: OtaStatus.connecting,
        message: 'Connecting to device…',
      ));
      await transport.connect();

      emit(const OtaProgress(
        status: OtaStatus.discoveringServices,
        message: 'Discovering OTA service…',
      ));
      await transport.discover();
      await transport.enableNotifications();

      _notificationSubscription = transport.notifications.listen((event) {
        _log.logRx('OTA', event);
        final completer = _pendingResponse;
        if (completer != null && !completer.isCompleted) {
          completer.complete(Uint8List.fromList(event));
        }
      });

      final mtu = await transport.requestMtu(AirocOtaConstants.requestedMtu);
      final chunkSize = AirocOtaProtocol.deriveChunkSize(mtu: mtu);
      _log.i('OTA', 'Chunk size: $chunkSize bytes  (MTU=$mtu)');

      emit(const OtaProgress(
        status: OtaStatus.preparingDownload,
        message: 'Entering bootloader…',
      ));

      // ── ENTER_BOOTLOADER ──────────────────────────────────────────────
      // Some bootloaders expect ENTER_BOOTLOADER with NO payload (no key),
      // others expect a 6-byte payload carrying a security/product key.
      // Try keyless first, then keyed variants, with checksum fallbacks.
      final checksumsToTry = <int>{
        AirocOtaConstants.sumChecksum,
        file.checksumType,
      }.toList();

      final keysToTry = <int>[];
      if (securityKeyOverride != null) keysToTry.add(securityKeyOverride);
      keysToTry.add(0);
      keysToTry.add(file.productId);
      keysToTry.add(_swap32(file.productId));
      keysToTry.add(file.siliconId);
      keysToTry.add(_swap32(file.siliconId));
      final uniqueKeys = keysToTry.toSet().toList();

      _log.i('OTA', 'ENTER_BOOTLOADER strategy: keyless first, then keyed');
      _log.i('OTA',
          'Checksums to try: ${checksumsToTry.map((c) => '0x${c.toRadixString(16)}').join(', ')}');
      _log.i('OTA',
          'Key candidates (${uniqueKeys.length}): ${uniqueKeys.map((k) => '0x${k.toRadixString(16).padLeft(8, '0')}').join(', ')}');

      AirocOtaResponse? enterResponse;
      String? acceptedMode;

      final attempts = <({String mode, Uint8List packet, int checksum})>[];
      // Keyless attempts first.
      for (final checksum in checksumsToTry) {
        attempts.add((
          mode: 'keyless, checksum=0x${checksum.toRadixString(16)}',
          packet: AirocOtaProtocol.buildPacket(
            command: AirocOtaConstants.cmdEnterBootloader,
            checksumType: checksum,
          ),
          checksum: checksum,
        ));
      }
      // Then keyed attempts.
      for (final key in uniqueKeys) {
        for (final checksum in checksumsToTry) {
          attempts.add((
            mode:
                'key=0x${key.toRadixString(16).padLeft(8, '0')}, checksum=0x${checksum.toRadixString(16)}',
            packet: AirocOtaProtocol.buildEnterBootloader(
              productId: key,
              checksumType: checksum,
            ),
            checksum: checksum,
          ));
        }
      }

      for (final attempt in attempts) {
        _log.i('OTA', 'ENTER_BOOTLOADER try: ${attempt.mode}');
        try {
          final resp = await _writeAndExpect(
            attempt.packet,
            checksumType: attempt.checksum,
            commandName: 'ENTER_BOOTLOADER',
          );

          if (resp.isSuccess) {
            enterResponse = resp;
            acceptedMode = attempt.mode;
            _log.i('OTA', 'ENTER_BOOTLOADER accepted ✓  ${attempt.mode}');
            break;
          }

          enterResponse = resp;
          if (resp.statusCode == AirocOtaConstants.statusErrData) {
            _log.w('OTA',
                'ENTER_BOOTLOADER rejected (CYRET_ERR_DATA) for ${attempt.mode}; trying next…');
            continue;
          }

          // Hard failure status codes stop probing.
          _log.e('OTA',
              'ENTER_BOOTLOADER hard failure for ${attempt.mode}: '
              '0x${resp.statusCode.toRadixString(16)} '
              '(${AirocOtaConstants.statusMessage(resp.statusCode)})');
          break;
        } on AirocOtaProtocolException catch (error) {
          // If checksum verification fails for one algorithm, keep probing with
          // other candidates.
          if (error.toString().contains('Checksum mismatch')) {
            _log.w('OTA',
                'ENTER_BOOTLOADER parse checksum mismatch for ${attempt.mode}; trying next…');
            continue;
          }
          rethrow;
        }
      }

      if (acceptedMode == null) {
        _log.e('OTA',
            'All ENTER_BOOTLOADER attempts failed. Please verify device is in '
            'OTA bootloader mode and firmware belongs to this exact target.');
      }

      _ensureSuccess(enterResponse!, 'ENTER_BOOTLOADER');
      final enterPayload =
          AirocOtaProtocol.parseEnterBootloaderPayload(enterResponse.payload);
      _log.i('OTA',
          'Bootloader response → siliconId=0x${enterPayload.siliconId.toRadixString(16)}  rev=${enterPayload.siliconRev}  btldrVer=${enterPayload.bootloaderVersion.map((b) => b.toRadixString(16)).join('.')}');
      if (file.siliconId != enterPayload.siliconId ||
          file.siliconRev != enterPayload.siliconRev) {
        _log.e('OTA',
            'SILICON MISMATCH  device=0x${enterPayload.siliconId.toRadixString(16)} rev=${enterPayload.siliconRev}  file=0x${file.siliconId.toRadixString(16)} rev=${file.siliconRev}');
        throw AirocOtaProtocolException(
          'Firmware silicon mismatch. Device=0x${enterPayload.siliconId.toRadixString(16)} '
          'rev ${enterPayload.siliconRev}, file=0x${file.siliconId.toRadixString(16)} '
          'rev ${file.siliconRev}.',
        );
      }
      _log.i('OTA', 'Silicon ID match ✓');

      bool supportsSetEiv = true;

      final metadataResponse = await _writeAndExpect(
        AirocOtaProtocol.buildSetAppMetadata(
          appId: file.appId,
          appStart: file.appStart,
          appSize: file.appSize,
          checksumType: file.checksumType,
        ),
        checksumType: file.checksumType,
        commandName: 'SET_APP_METADATA',
      );
      if (metadataResponse.statusCode == AirocOtaConstants.statusErrCommand) {
        _log.w(
          'OTA',
          'SET_APP_METADATA is not supported by this bootloader '
          '(CYRET_ERR_CMD). Switching to compatibility mode and continuing.',
        );
        supportsSetEiv = false;
      } else {
        _ensureSuccess(metadataResponse, 'SET_APP_METADATA');
        _log.i('OTA', 'SET_APP_METADATA ✓');
      }

      final totalBytes = file.size;
      var useLegacyProgramRow = false;
      emit(OtaProgress(
        status: OtaStatus.transferring,
        totalBytes: totalBytes,
        message: 'Transferring firmware…',
      ));

      for (final row in file.rows) {
        _throwIfCancelled();
        if (row.isEiv) {
          if (!supportsSetEiv) {
            _log.w('OTA', 'Skipping EIV row because SET_EIV is unsupported.');
            continue;
          }
          final eivResponse = await _writeAndExpect(
            AirocOtaProtocol.buildSetEiv(
              eiv: row.data,
              checksumType: file.checksumType,
            ),
            checksumType: file.checksumType,
            commandName: 'SET_EIV',
          );
          if (eivResponse.statusCode == AirocOtaConstants.statusErrCommand) {
            supportsSetEiv = false;
            _log.w(
              'OTA',
              'SET_EIV is not supported by this bootloader (CYRET_ERR_CMD). '
              'Continuing without EIV.',
            );
            continue;
          }
          _ensureSuccess(eivResponse, 'SET_EIV');
          _log.i('OTA', 'SET_EIV ✓');
          continue;
        }

        var offset = 0;
        final legacyRow = _legacyRowAddress(file, row);
        while (offset < row.data.length) {
          _throwIfCancelled();
          final remaining = row.data.length - offset;
          final isLastChunk = remaining <= chunkSize;
          final chunk = Uint8List.sublistView(
            row.data,
            offset,
            offset + (isLastChunk ? remaining : chunkSize),
          );

          final sendWithProgramRow =
              isLastChunk && useLegacyProgramRow && legacyRow != null;

          final cmdName = !isLastChunk
              ? 'SEND_DATA'
              : (sendWithProgramRow ? 'PROGRAM_ROW' : 'PROGRAM_DATA');

          var response = await _writeAndExpect(
            !isLastChunk
                ? AirocOtaProtocol.buildSendData(
                    data: chunk,
                    checksumType: file.checksumType,
                  )
                : sendWithProgramRow
                    ? AirocOtaProtocol.buildProgramRow(
                        arrayId: legacyRow.arrayId,
                        rowNumber: legacyRow.rowNumber,
                        data: chunk,
                        checksumType: file.checksumType,
                      )
                    : AirocOtaProtocol.buildProgramData(
                        address: row.address!,
                        crc32: row.crc32!,
                        data: chunk,
                        checksumType: file.checksumType,
                      ),
            checksumType: file.checksumType,
            commandName: cmdName,
          );

          // Compatibility fallback: some bootloaders do not support PROGRAM_DATA.
          if (isLastChunk &&
              !useLegacyProgramRow &&
              legacyRow != null &&
              cmdName == 'PROGRAM_DATA' &&
              response.statusCode == AirocOtaConstants.statusErrCommand) {
            _log.w(
              'OTA',
              'PROGRAM_DATA is unsupported (CYRET_ERR_CMD). '
              'Switching to legacy PROGRAM_ROW mode for remaining rows.',
            );
            useLegacyProgramRow = true;
            response = await _writeAndExpect(
              AirocOtaProtocol.buildProgramRow(
                arrayId: legacyRow.arrayId,
                rowNumber: legacyRow.rowNumber,
                data: chunk,
                checksumType: file.checksumType,
              ),
              checksumType: file.checksumType,
              commandName: 'PROGRAM_ROW',
            );
            _ensureSuccess(response, 'PROGRAM_ROW');
          } else {
            _ensureSuccess(response, cmdName);
          }

          offset += chunk.length;
          _bytesTransferred += chunk.length;
          // Log every ~10 % progress milestone.
          if (totalBytes > 0) {
            final pct = (_bytesTransferred / totalBytes * 100).round();
            if (pct % 10 == 0) {
              _log.i('OTA', 'Transfer progress: $pct%  ($_bytesTransferred / $totalBytes bytes)');
            }
          }
          emit(OtaProgress(
            status: OtaStatus.transferring,
            totalBytes: totalBytes,
            bytesTransferred: _bytesTransferred,
            progress: totalBytes == 0
                ? 0
                : (_bytesTransferred / totalBytes) * 100,
            message: 'Transferred $_bytesTransferred / $totalBytes bytes',
          ));
        }
      }

      emit(OtaProgress(
        status: OtaStatus.verifying,
        bytesTransferred: _bytesTransferred,
        totalBytes: totalBytes,
        progress: 100,
        message: 'Verifying application image…',
      ));
      final verifyResponse = await _verifyAppWithCompatibility(
        appId: file.appId,
        checksumType: file.checksumType,
      );
      _log.i('OTA',
          'VERIFY_APP ✓  application image is valid  payload=${verifyResponse.payload.toList()}');

      _log.i('OTA', 'Sending EXIT_BOOTLOADER…');
      await transport.write(
        AirocOtaProtocol.buildExitBootloader(
          checksumType: file.checksumType,
        ),
      );

      _log.i('OTA', '══════════ OTA SUCCESS  totalBytes=$_bytesTransferred  elapsed=${stopwatch.elapsedMilliseconds}ms ══════════');
      emit(OtaProgress(
        status: OtaStatus.success,
        bytesTransferred: _bytesTransferred,
        totalBytes: totalBytes,
        progress: 100,
        message: 'OTA upgrade completed successfully.',
      ));

      return OtaResult.success(
        bytesTransferred: _bytesTransferred,
        duration: stopwatch.elapsed,
      );
    } on _OtaCancelledException {
      _log.w('OTA', 'OTA cancelled by user  bytesTransferred=$_bytesTransferred');
      emit(OtaProgress(
        status: OtaStatus.aborted,
        bytesTransferred: _bytesTransferred,
        message: 'OTA upgrade cancelled.',
      ));
      return OtaResult.aborted();
    } catch (error, stackTrace) {
      _log.e('OTA', 'OTA FAILED: $error');
      _log.e('OTA', 'StackTrace:\n$stackTrace');
      emit(OtaProgress(
        status: OtaStatus.failed,
        bytesTransferred: _bytesTransferred,
        message: error.toString(),
      ));
      return OtaResult.failure(
        errorMessage: error.toString(),
        bytesTransferred: _bytesTransferred,
        duration: stopwatch.elapsed,
      );
    } finally {
      stopwatch.stop();
      await _notificationSubscription?.cancel();
      _notificationSubscription = null;
      _pendingResponse = null;
      await transport.disconnect();
    }
  }

  Future<void> dispose() async {
    await _notificationSubscription?.cancel();
    await _progressController.close();
  }

  Future<AirocOtaResponse> _writeAndExpect(
    Uint8List packet, {
    required int checksumType,
    String commandName = 'CMD',
  }) async {
    _log.v('OTA', 'Writing $commandName  (${packet.length} bytes)');
    final completer = Completer<Uint8List>();
    _pendingResponse = completer;
    await transport.write(packet);
    try {
      final responseBytes = await completer.future.timeout(
        AirocOtaConstants.controlPointTimeout,
        onTimeout: () {
          _log.e('OTA', '$commandName TIMEOUT — no response within ${AirocOtaConstants.controlPointTimeout.inSeconds}s');
          throw TimeoutException('$commandName timed out', AirocOtaConstants.controlPointTimeout);
        },
      );
      final response = AirocOtaProtocol.parseResponse(
        responseBytes,
        checksumType: checksumType,
      );
      if (response.isSuccess) {
        _log.v('OTA', '$commandName response: SUCCESS  payload=${response.payload.length} bytes');
      } else {
        _log.e('OTA', '$commandName response: ERROR  statusCode=0x${response.statusCode.toRadixString(16)}  (${AirocOtaConstants.statusMessage(response.statusCode)})');
      }
      return response;
    } finally {
      if (identical(_pendingResponse, completer)) {
        _pendingResponse = null;
      }
    }
  }

  Future<AirocOtaResponse> _verifyAppWithCompatibility({
    required int appId,
    required int checksumType,
  }) async {
    final checksumCandidates = <int>{checksumType, AirocOtaConstants.sumChecksum}.toList();
    final variants = <({String name, Uint8List Function(int checksumType) build})>[
      (
        name: 'appId=$appId',
        build: (cs) => AirocOtaProtocol.buildVerifyApp(
              appId: appId,
              checksumType: cs,
            ),
      ),
      if (appId != 0)
        (
          name: 'appId=0',
          build: (cs) => AirocOtaProtocol.buildVerifyApp(
                appId: 0,
                checksumType: cs,
              ),
        ),
      (
        // Some legacy stacks expect VERIFY_APP without payload.
        name: 'no-payload',
        build: (cs) => AirocOtaProtocol.buildPacket(
              command: AirocOtaConstants.cmdVerifyApp,
              checksumType: cs,
            ),
      ),
    ];

    AirocOtaResponse? lastResponse;

    for (final variant in variants) {
      for (final cs in checksumCandidates) {
        for (var attempt = 1;
            attempt <= AirocOtaConstants.verifyAppRetryCount + 1;
            attempt++) {
          final response = await _writeAndExpect(
            variant.build(cs),
            checksumType: cs,
            commandName: 'VERIFY_APP (${variant.name}, cs=0x${cs.toRadixString(16)})',
          );
          lastResponse = response;

          if (response.isSuccess) {
            final payload = response.payload;
            if (payload.isEmpty || payload.first == 1) {
              return response;
            }
            _log.e('OTA',
                'VERIFY_APP returned non-success payload for ${variant.name}: ${payload.toList()}');
            throw const AirocOtaProtocolException(
              'VERIFY_APP returned an invalid application status.',
            );
          }

          if (response.statusCode == AirocOtaConstants.statusErrData &&
              attempt <= AirocOtaConstants.verifyAppRetryCount) {
            _log.w(
              'OTA',
              'VERIFY_APP ERR_DATA for ${variant.name} '
              '(attempt $attempt/${AirocOtaConstants.verifyAppRetryCount + 1}). '
              'Retrying after ${AirocOtaConstants.verifyAppRetryDelay.inMilliseconds} ms…',
            );
            await Future<void>.delayed(AirocOtaConstants.verifyAppRetryDelay);
            continue;
          }

          // Try next variant when command/payload shape seems unsupported.
          if (response.statusCode == AirocOtaConstants.statusErrData ||
              response.statusCode == AirocOtaConstants.statusErrCommand) {
            _log.w('OTA',
                'VERIFY_APP variant rejected (${variant.name}, cs=0x${cs.toRadixString(16)}), '
                'status=0x${response.statusCode.toRadixString(16)}. Trying next variant…');
            break;
          }

          // Hard failure codes (e.g. ERR_APP) should stop immediately.
          _ensureSuccess(response, 'VERIFY_APP');
        }
      }
    }

    _ensureSuccess(lastResponse!, 'VERIFY_APP');
    throw StateError('VERIFY_APP failed unexpectedly without throwing.');
  }

  void _ensureSuccess(AirocOtaResponse response, String commandName) {
    if (!response.isSuccess) {
      final code = response.statusCode;
      final msg = AirocOtaConstants.statusMessage(code);
      // Build a context-aware hint for the most common failure codes.
      final hint = _hintForStatus(code, commandName);
      _log.e('OTA',
          '$commandName FAILED  statusCode=0x${code.toRadixString(16)} ($msg)$hint');
      throw AirocOtaProtocolException(
        '$commandName failed: $msg${hint.isNotEmpty ? '\n$hint' : ''}',
      );
    }
  }

  /// Returns a human-readable diagnostic hint for well-known status+command
  /// combinations, or an empty string when no specific hint is available.
  static String _hintForStatus(int code, String commandName) {
    if (code == AirocOtaConstants.statusErrData) {
      if (commandName.contains('ENTER_BOOTLOADER')) {
        return '\nHint: Device rejected ENTER_BOOTLOADER payload. '
            'Host already auto-tried keyless and keyed payload variants '
            'with checksum fallbacks (SUM/CRC). '
            'Check bootloader mode, firmware compatibility, and OTA UUID pair '
            '(service=00060000, characteristic=00060001).';
      }
      if (commandName.contains('PROGRAM_DATA')) {
        return '\nHint: The device rejected a data chunk (bad CRC or address). '
            'The firmware file may be corrupt or incompatible.';
      }
      if (commandName.contains('VERIFY_APP')) {
        return '\nHint: VERIFY_APP still reports ERR_DATA after automatic '
            'compatibility retries and variant fallbacks '
            '(appId, appId=0, no-payload, SUM/CRC). The transferred image may '
            'not match the active app slot or is incompatible with this target.';
      }
    }
    if (code == AirocOtaConstants.statusErrChecksum) {
      return '\nHint: Packet checksum mismatch. Verify the checksumType '
          'field in the firmware file matches the device bootloader.';
    }
    if (code == AirocOtaConstants.statusErrCommand &&
        commandName.contains('PROGRAM_DATA')) {
      return '\nHint: This bootloader does not support PROGRAM_DATA. '
          'Host should auto-fallback to PROGRAM_ROW for legacy cyacd rows.';
    }
    if (code == AirocOtaConstants.statusErrApp) {
      return '\nHint: The application image failed verification (VERIFY_APP). '
          'The firmware may be incomplete or incompatible with this device.';
    }
    if (code == AirocOtaConstants.statusErrVersion) {
      return '\nHint: Firmware version is not accepted by the bootloader.';
    }
    if (code == AirocOtaConstants.statusErrDevice) {
      return '\nHint: The device reported an internal error. '
          'Try power-cycling the device and retrying.';
    }
    return '';
  }

  static int _swap32(int value) {
    final v = value & 0xFFFFFFFF;
    return ((v & 0x000000FF) << 24) |
        ((v & 0x0000FF00) << 8) |
        ((v & 0x00FF0000) >> 8) |
        ((v & 0xFF000000) >> 24);
  }

  static _LegacyRowAddress? _legacyRowAddress(OtaFile file, OtaFileRow row) {
    // Legacy PROGRAM_ROW addressing is reliably available for cyacd rows
    // where address is encoded as [arrayId:8][rowNumber:16].
    if (file.fileType != OtaFileType.cyacd || row.address == null) {
      return null;
    }
    final raw = row.address!;
    return _LegacyRowAddress(
      arrayId: (raw >> 16) & 0xFF,
      rowNumber: raw & 0xFFFF,
    );
  }

  void _throwIfCancelled() {
    if (_cancelRequested) {
      throw const _OtaCancelledException();
    }
  }
}

class _OtaCancelledException implements Exception {
  const _OtaCancelledException();
}

class _LegacyRowAddress {
  final int arrayId;
  final int rowNumber;

  const _LegacyRowAddress({
    required this.arrayId,
    required this.rowNumber,
  });
}


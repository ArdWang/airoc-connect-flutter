import 'dart:async';
import 'dart:typed_data';

import 'package:airoc_connect_flutter/src/ota/airoc_ota_constants.dart';
import 'package:airoc_connect_flutter/src/ota/airoc_ota_protocol.dart';
import 'package:airoc_connect_flutter/src/ota/airoc_ota_service.dart';

/// Fake transport used by tests to simulate a complete OTA session.
class FakeOtaTransport implements AirocOtaTransport {
  final StreamController<List<int>> _notifications =
      StreamController<List<int>>.broadcast();

  final List<Uint8List> writes = <Uint8List>[];
  final int siliconId;
  final int siliconRev;
  final bool verifySuccess;
  final List<int>? verifyStatusSequence;
  final bool verifyRequiresNoPayload;
  final int mtu;
  final bool rejectProgramData;
  int _verifyCallCount = 0;

  FakeOtaTransport({
    required this.siliconId,
    required this.siliconRev,
    this.verifySuccess = true,
    this.verifyStatusSequence,
    this.verifyRequiresNoPayload = false,
    this.mtu = 247,
    this.rejectProgramData = false,
  });

  @override
  Stream<List<int>> get notifications => _notifications.stream;

  @override
  Future<void> connect() async {}

  @override
  Future<void> discover() async {}

  @override
  Future<void> enableNotifications() async {}

  @override
  Future<int> requestMtu(int desiredMtu) async => mtu;

  @override
  Future<void> write(List<int> data, {bool withoutResponse = false}) async {
    final packet = Uint8List.fromList(data);
    writes.add(packet);

    final command = packet[1];
    Uint8List? response;
    switch (command) {
      case AirocOtaConstants.cmdEnterBootloader:
        response = _responsePacket(
          statusCode: AirocOtaConstants.statusSuccess,
          payload: <int>[
            ...AirocOtaProtocol.uint32ToLeBytes(siliconId),
            siliconRev,
            0x01,
            0x00,
            0x00,
          ],
        );
        break;
      case AirocOtaConstants.cmdSetAppMetadata:
      case AirocOtaConstants.cmdSetEiv:
      case AirocOtaConstants.cmdSendData:
      case AirocOtaConstants.cmdProgramData:
        response = rejectProgramData
            ? _responsePacket(statusCode: AirocOtaConstants.statusErrCommand)
            : _successResponse(command);
        break;
      case AirocOtaConstants.cmdProgramRow:
        response = _successResponse(command);
        break;
      case AirocOtaConstants.cmdVerifyApp:
        final payloadLength = (packet[2] & 0xFF) | ((packet[3] & 0xFF) << 8);
        if (verifyRequiresNoPayload && payloadLength > 0) {
          response = _responsePacket(statusCode: AirocOtaConstants.statusErrData);
          break;
        }
        final statusFromSequence = verifyStatusSequence != null &&
                _verifyCallCount < verifyStatusSequence!.length
            ? verifyStatusSequence![_verifyCallCount]
            : null;
        _verifyCallCount++;
        final statusCode = statusFromSequence ?? AirocOtaConstants.statusSuccess;
        response = _responsePacket(
          statusCode: statusCode,
          payload: statusCode == AirocOtaConstants.statusSuccess
              ? <int>[verifySuccess ? 1 : 0]
              : const <int>[],
        );
        break;
      case AirocOtaConstants.cmdExitBootloader:
        response = null;
        break;
      default:
        response = _successResponse(command);
        break;
    }

    if (response != null) {
      unawaited(Future<void>.microtask(() => _notifications.add(response!)));
    }
  }

  Uint8List _successResponse(int command) {
    return _responsePacket(statusCode: AirocOtaConstants.statusSuccess);
  }

  Uint8List _responsePacket({
    required int statusCode,
    List<int> payload = const <int>[],
  }) {
    final dataLength = payload.length;
    final packetLength = AirocOtaConstants.basePacketSize + dataLength;
    final bytes = Uint8List(packetLength);

    var i = 0;
    bytes[i++] = AirocOtaConstants.packetStart;
    bytes[i++] = statusCode & 0xFF;
    bytes[i++] = dataLength & 0xFF;
    bytes[i++] = (dataLength >> 8) & 0xFF;
    for (final b in payload) {
      bytes[i++] = b & 0xFF;
    }

    final checksum = AirocOtaProtocol.calculatePacketChecksum(
      checksumType: AirocOtaConstants.sumChecksum,
      bytes: bytes,
      length: i,
    );
    bytes[i++] = checksum & 0xFF;
    bytes[i++] = (checksum >> 8) & 0xFF;
    bytes[i] = AirocOtaConstants.packetEnd;
    return bytes;
  }

  @override
  Future<void> disconnect() async {}

  Future<void> dispose() => _notifications.close();
}


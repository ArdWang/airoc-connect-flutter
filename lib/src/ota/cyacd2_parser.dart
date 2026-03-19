import 'dart:convert';
import 'dart:typed_data';

import 'airoc_ota_protocol.dart';
import 'ota_file.dart';

/// Thrown when a CYACD2 file cannot be parsed.
class Cyacd2ParseException implements Exception {
  final String message;

  const Cyacd2ParseException(this.message);

  @override
  String toString() => 'Cyacd2ParseException: $message';
}

/// Parser for Infineon/Cypress CYACD2 firmware files.
class Cyacd2Parser {
  Cyacd2Parser._();

  static OtaFile parse(
    Uint8List bytes, {
    String fileName = 'firmware.cyacd2',
  }) {
    final content = utf8.decode(bytes, allowMalformed: false);
    return parseString(content, fileName: fileName);
  }

  static OtaFile parseString(
    String content, {
    String fileName = 'firmware.cyacd2',
  }) {
    final lines = content
        .split(RegExp(r'\r?\n'))
        .map(_sanitizeLine)
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      throw const Cyacd2ParseException('File is empty.');
    }

    final header = _parseHeader(lines.first);
    final rows = <OtaFileRow>[];
    int? appStart;
    int? appSize;

    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('@APPINFO:0x')) {
        final metadata = _parseAppInfo(line, i + 1);
        appStart = metadata.$1;
        appSize = metadata.$2;
      } else if (line.startsWith('@EIV:')) {
        rows.add(_parseEivRow(line, i + 1));
      } else if (line.startsWith(':')) {
        rows.add(_parseDataRow(line, i + 1));
      } else {
        throw Cyacd2ParseException(
          'Line ${i + 1}: unsupported row format "$line".',
        );
      }
    }

    if (rows.isEmpty) {
      throw const Cyacd2ParseException('No transferable rows were found.');
    }

    appStart ??= rows
        .where((row) => row.isData)
        .map((row) => row.address!)
        .fold<int>(0xFFFFFFFF, (min, value) => value < min ? value : min);
    appSize ??= rows
        .where((row) => row.isData)
        .fold<int>(0, (sum, row) => sum + row.data.length);

    return OtaFile(
      fileName: fileName,
      fileType: OtaFileType.cyacd2,
      firmwareVersion: header.fileVersion,
      appId: header.appId,
      productId: header.productId,
      siliconId: header.siliconId,
      siliconRev: header.siliconRev,
      checksumType: header.checksumType,
      appStart: appStart,
      appSize: appSize,
      rows: rows,
    );
  }

  static String _sanitizeLine(String input) {
    final allowed = RegExp(r'[A-Za-z0-9@:,x]');
    return input
        .trim()
        .split('')
        .where((char) => allowed.hasMatch(char))
        .join();
  }

  static _Cyacd2Header _parseHeader(String line) {
    if (line.length < 24) {
      throw Cyacd2ParseException(
        'Header must be at least 24 hex characters, got ${line.length}.',
      );
    }

    try {
      final fileVersion = int.parse(line.substring(0, 2), radix: 16);
      if (fileVersion != 1) {
        throw Cyacd2ParseException(
          'Unsupported CYACD2 file version: $fileVersion.',
        );
      }

      return _Cyacd2Header(
        fileVersion: fileVersion,
        siliconId: _parseLittleEndianHex(line.substring(2, 10)),
        siliconRev: int.parse(line.substring(10, 12), radix: 16),
        checksumType: int.parse(line.substring(12, 14), radix: 16),
        appId: int.parse(line.substring(14, 16), radix: 16),
        productId: _parseLittleEndianHex(line.substring(16, 24)),
      );
    } on FormatException catch (error) {
      throw Cyacd2ParseException('Invalid header: $error');
    }
  }

  static (int, int) _parseAppInfo(String line, int lineNumber) {
    final body = line.substring('@APPINFO:0x'.length);
    final parts = body.split(',0x');
    if (parts.length != 2) {
      throw Cyacd2ParseException(
        'Line $lineNumber: APPINFO row is malformed.',
      );
    }

    try {
      return (
        int.parse(parts[0], radix: 16),
        int.parse(parts[1], radix: 16),
      );
    } on FormatException catch (error) {
      throw Cyacd2ParseException('Line $lineNumber: invalid APPINFO: $error');
    }
  }

  static OtaFileRow _parseEivRow(String line, int lineNumber) {
    final hexData = line.substring('@EIV:'.length);
    if (hexData.length.isOdd) {
      throw Cyacd2ParseException(
        'Line $lineNumber: EIV row must contain an even number of hex digits.',
      );
    }

    return OtaFileRow(
      type: OtaRowType.eiv,
      data: _hexDecode(hexData, lineNumber),
    );
  }

  static OtaFileRow _parseDataRow(String line, int lineNumber) {
    final body = line.substring(1);
    if (body.length < 8 || body.length.isOdd) {
      throw Cyacd2ParseException(
        'Line $lineNumber: data row must contain a 4-byte address and even-length payload.',
      );
    }

    final address = _parseLittleEndianHex(body.substring(0, 8));
    final data = _hexDecode(body.substring(8), lineNumber);

    return OtaFileRow(
      type: OtaRowType.data,
      address: address,
      crc32: AirocOtaProtocol.crc32(data),
      data: data,
    );
  }

  static Uint8List _hexDecode(String hex, int lineNumber) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      final value = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      if (value == null) {
        throw Cyacd2ParseException(
          'Line $lineNumber: invalid hex data.',
        );
      }
      bytes[i] = value;
    }
    return bytes;
  }

  static int _parseLittleEndianHex(String hex) {
    final bytes = _hexDecode(hex, 1);
    var value = 0;
    for (var i = 0; i < bytes.length; i++) {
      value |= (bytes[i] & 0xFF) << (8 * i);
    }
    return value;
  }
}

class _Cyacd2Header {
  final int fileVersion;
  final int siliconId;
  final int siliconRev;
  final int checksumType;
  final int appId;
  final int productId;

  const _Cyacd2Header({
    required this.fileVersion,
    required this.siliconId,
    required this.siliconRev,
    required this.checksumType,
    required this.appId,
    required this.productId,
  });
}

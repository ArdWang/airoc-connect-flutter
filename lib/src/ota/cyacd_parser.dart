import 'dart:convert';
import 'dart:typed_data';

import 'airoc_ota_protocol.dart';
import 'cyacd2_parser.dart';
import 'ota_file.dart';

/// Thrown when a CYACD file cannot be parsed.
class CyacdParseException implements Exception {
  final String message;

  const CyacdParseException(this.message);

  @override
  String toString() => 'CyacdParseException: $message';
}

/// Parser for legacy Infineon/Cypress CYACD firmware files.
///
/// The parser accepts two common variants:
/// 1) Legacy row format: `:AA RRRR LLLL <data> CC`
/// 2) CYACD2-like payloads stored with a `.cyacd` extension.
class CyacdParser {
  CyacdParser._();

  static OtaFile parse(
    Uint8List bytes, {
    String fileName = 'firmware.cyacd',
  }) {
    final content = utf8.decode(bytes, allowMalformed: false);
    return parseString(content, fileName: fileName);
  }

  static OtaFile parseString(
    String content, {
    String fileName = 'firmware.cyacd',
  }) {
    final lines = content
        .split(RegExp(r'\r?\n'))
        .map(_sanitizeLine)
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      throw const CyacdParseException('File is empty.');
    }

    // Some toolchains still output CYACD2 text but save it as .cyacd.
    // Reuse the CYACD2 parser first to keep compatibility.
    try {
      final parsed = Cyacd2Parser.parseString(content, fileName: fileName);
      return OtaFile(
        fileName: parsed.fileName,
        fileType: OtaFileType.cyacd,
        firmwareVersion: parsed.firmwareVersion,
        appId: parsed.appId,
        productId: parsed.productId,
        siliconId: parsed.siliconId,
        siliconRev: parsed.siliconRev,
        checksumType: parsed.checksumType,
        appStart: parsed.appStart,
        appSize: parsed.appSize,
        rows: parsed.rows,
      );
    } on Cyacd2ParseException {
      // Fallback to legacy CYACD format.
    }

    final header = _parseHeader(lines.first);
    final rows = <OtaFileRow>[];

    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('#') || line.startsWith(';')) {
        continue;
      }
      if (!line.startsWith(':')) {
        throw CyacdParseException(
          'Line ${i + 1}: unsupported row format "$line".',
        );
      }
      rows.add(_parseDataRow(line, i + 1));
    }

    if (rows.isEmpty) {
      throw const CyacdParseException('No transferable rows were found.');
    }

    final appStart = rows
        .map((row) => row.address!)
        .reduce((min, value) => value < min ? value : min);
    final appSize = rows.fold<int>(0, (sum, row) => sum + row.data.length);

    return OtaFile(
      fileName: fileName,
      fileType: OtaFileType.cyacd,
      firmwareVersion: 0,
      appId: 1,
      // Legacy CYACD does not carry a product ID. Use silicon ID as a stable
      // non-zero fallback so ENTER_BOOTLOADER payload is not empty.
      productId: header.siliconId,
      siliconId: header.siliconId,
      siliconRev: header.siliconRev,
      checksumType: header.checksumType,
      appStart: appStart,
      appSize: appSize,
      rows: rows,
    );
  }

  static String _sanitizeLine(String input) {
    final allowed = RegExp(r'[A-Za-z0-9#;:@]');
    return input
        .trim()
        .split('')
        .where((char) => allowed.hasMatch(char))
        .join();
  }

  static _CyacdHeader _parseHeader(String line) {
    if (!RegExp(r'^[0-9A-Fa-f]{12,}$').hasMatch(line)) {
      throw CyacdParseException(
        'Header must contain at least 12 hex characters, got "$line".',
      );
    }

    try {
      final siliconId = int.parse(line.substring(0, 8), radix: 16);
      final siliconRev = int.parse(line.substring(8, 10), radix: 16);
      final checksumType = int.parse(line.substring(10, 12), radix: 16);
      return _CyacdHeader(
        siliconId: siliconId,
        siliconRev: siliconRev,
        checksumType: checksumType,
      );
    } on FormatException catch (error) {
      throw CyacdParseException('Invalid header: $error');
    }
  }

  static OtaFileRow _parseDataRow(String line, int lineNumber) {
    final body = line.substring(1);
    if (body.length < 12) {
      throw CyacdParseException(
        'Line $lineNumber: data row is too short.',
      );
    }

    try {
      final arrayId = int.parse(body.substring(0, 2), radix: 16);
      final rowNumber = int.parse(body.substring(2, 6), radix: 16);
      final dataLength = int.parse(body.substring(6, 10), radix: 16);

      final expectedLength = 2 + 4 + 4 + (dataLength * 2) + 2;
      if (body.length != expectedLength) {
        throw CyacdParseException(
          'Line $lineNumber: length mismatch. Declared payload $dataLength bytes, '
          'line length is ${body.length} hex chars.',
        );
      }

      final dataHex = body.substring(10, 10 + dataLength * 2);
      final data = _hexDecode(dataHex, lineNumber);

      // Keep a deterministic 24-bit address-like key for the OTA transfer path.
      final address = ((arrayId & 0xFF) << 16) | (rowNumber & 0xFFFF);

      return OtaFileRow(
        type: OtaRowType.data,
        address: address,
        crc32: AirocOtaProtocol.crc32(data),
        data: data,
      );
    } on FormatException catch (error) {
      throw CyacdParseException('Line $lineNumber: invalid row: $error');
    }
  }

  static Uint8List _hexDecode(String hex, int lineNumber) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      final value = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      if (value == null) {
        throw CyacdParseException('Line $lineNumber: invalid hex data.');
      }
      bytes[i] = value;
    }
    return bytes;
  }
}

class _CyacdHeader {
  final int siliconId;
  final int siliconRev;
  final int checksumType;

  const _CyacdHeader({
    required this.siliconId,
    required this.siliconRev,
    required this.checksumType,
  });
}


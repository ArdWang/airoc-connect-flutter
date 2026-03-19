import 'dart:typed_data';

/// Supported OTA firmware file formats.
enum OtaFileType {
  /// Legacy Cypress Application Code And Data.
  cyacd,

  /// Cypress Application Code And Data v2.
  cyacd2,

  /// Unsupported or unrecognized format.
  unknown,
}

/// The type of a parsed firmware row.
enum OtaRowType {
  /// Firmware data row containing an address and binary payload.
  data,

  /// Encryption initialization-vector row.
  eiv,
}

/// One transferable row from a firmware file.
class OtaFileRow {
  final OtaRowType type;
  final Uint8List data;
  final int? address;
  final int? crc32;

  const OtaFileRow({
    required this.type,
    required this.data,
    this.address,
    this.crc32,
  });

  bool get isData => type == OtaRowType.data;
  bool get isEiv => type == OtaRowType.eiv;
  int get size => data.length;

  @override
  String toString() =>
      'OtaFileRow(type: $type, address: $address, size: ${data.length})';
}

/// Parsed OTA firmware image ready for transfer to a device.
class OtaFile {
  final String fileName;
  final OtaFileType fileType;
  final int firmwareVersion;
  final int appId;
  final int productId;
  final int siliconId;
  final int siliconRev;
  final int checksumType;
  final int appStart;
  final int appSize;
  final List<OtaFileRow> rows;

  const OtaFile({
    required this.fileName,
    required this.fileType,
    required this.firmwareVersion,
    required this.appId,
    required this.productId,
    required this.siliconId,
    required this.siliconRev,
    required this.checksumType,
    required this.appStart,
    required this.appSize,
    required this.rows,
  });

  /// Total binary bytes transported to the device.
  int get size => rows.fold<int>(0, (sum, row) => sum + row.data.length);

  /// Aggregated firmware data bytes.
  Uint8List get data {
    final builder = BytesBuilder(copy: false);
    for (final row in rows) {
      builder.add(row.data);
    }
    return builder.toBytes();
  }

  /// Whether the file contains at least one transferable row.
  bool get isValid => rows.isNotEmpty;

  /// The number of actual program-data rows.
  int get dataRowCount => rows.where((row) => row.isData).length;

  @override
  String toString() =>
      'OtaFile(name: $fileName, type: $fileType, rows: ${rows.length}, '
      'size: $size, appId: $appId, productId: $productId, '
      'siliconId: 0x${siliconId.toRadixString(16)})';
}

import 'dart:typed_data';

import 'airoc_ota_constants.dart';

/// Exception thrown when an OTA bootloader packet is invalid.
class AirocOtaProtocolException implements Exception {
  final String message;

  const AirocOtaProtocolException(this.message);

  @override
  String toString() => 'AirocOtaProtocolException: $message';
}

/// Parsed OTA bootloader response packet.
class AirocOtaResponse {
  final int statusCode;
  final Uint8List payload;

  const AirocOtaResponse({
    required this.statusCode,
    required this.payload,
  });

  bool get isSuccess => statusCode == AirocOtaConstants.statusSuccess;
}

/// Parsed payload returned by ENTER_BOOTLOADER.
class EnterBootloaderResponse {
  final int siliconId;
  final int siliconRev;
  final Uint8List bootloaderVersion;

  const EnterBootloaderResponse({
    required this.siliconId,
    required this.siliconRev,
    required this.bootloaderVersion,
  });
}

/// Helpers to build and parse Infineon AIROC bootloader v1 packets.
class AirocOtaProtocol {
  AirocOtaProtocol._();

  static Uint8List buildPacket({
    required int command,
    List<int> payload = const [],
    int checksumType = AirocOtaConstants.sumChecksum,
  }) {
    final dataLength = payload.length;
    final packetLength = AirocOtaConstants.basePacketSize + dataLength;
    final bytes = Uint8List(packetLength);
    var index = 0;
    bytes[index++] = AirocOtaConstants.packetStart;
    bytes[index++] = command;
    bytes[index++] = dataLength & 0xFF;
    bytes[index++] = (dataLength >> 8) & 0xFF;
    for (final value in payload) {
      bytes[index++] = value & 0xFF;
    }

    final checksum = calculatePacketChecksum(
      checksumType: checksumType,
      bytes: bytes,
      length: index,
    );
    bytes[index++] = checksum & 0xFF;
    bytes[index++] = (checksum >> 8) & 0xFF;
    bytes[index] = AirocOtaConstants.packetEnd;
    return bytes;
  }

  static Uint8List buildEnterBootloader({
    required int productId,
    required int checksumType,
  }) {
    return buildPacket(
      command: AirocOtaConstants.cmdEnterBootloader,
      checksumType: checksumType,
      payload: <int>[
        ...uint32ToLeBytes(productId),
        0x00,
        0x00,
      ],
    );
  }

  static Uint8List buildSetAppMetadata({
    required int appId,
    required int appStart,
    required int appSize,
    required int checksumType,
  }) {
    return buildPacket(
      command: AirocOtaConstants.cmdSetAppMetadata,
      checksumType: checksumType,
      payload: <int>[
        appId & 0xFF,
        ...uint32ToLeBytes(appStart),
        ...uint32ToLeBytes(appSize),
      ],
    );
  }

  static Uint8List buildSetEiv({
    required Uint8List eiv,
    required int checksumType,
  }) {
    return buildPacket(
      command: AirocOtaConstants.cmdSetEiv,
      checksumType: checksumType,
      payload: eiv,
    );
  }

  static Uint8List buildSendData({
    required Uint8List data,
    required int checksumType,
    bool withoutResponse = false,
  }) {
    return buildPacket(
      command: withoutResponse
          ? AirocOtaConstants.cmdSendDataWithoutResponse
          : AirocOtaConstants.cmdSendData,
      checksumType: checksumType,
      payload: data,
    );
  }

  static Uint8List buildProgramData({
    required int address,
    required int crc32,
    required Uint8List data,
    required int checksumType,
  }) {
    return buildPacket(
      command: AirocOtaConstants.cmdProgramData,
      checksumType: checksumType,
      payload: <int>[
        ...uint32ToLeBytes(address),
        ...uint32ToLeBytes(crc32),
        ...data,
      ],
    );
  }

  static Uint8List buildProgramRow({
    required int arrayId,
    required int rowNumber,
    required Uint8List data,
    required int checksumType,
  }) {
    return buildPacket(
      command: AirocOtaConstants.cmdProgramRow,
      checksumType: checksumType,
      payload: <int>[
        arrayId & 0xFF,
        rowNumber & 0xFF,
        (rowNumber >> 8) & 0xFF,
        ...data,
      ],
    );
  }

  static Uint8List buildVerifyApp({
    required int appId,
    required int checksumType,
  }) {
    return buildPacket(
      command: AirocOtaConstants.cmdVerifyApp,
      checksumType: checksumType,
      payload: <int>[appId & 0xFF],
    );
  }

  static Uint8List buildExitBootloader({required int checksumType}) {
    return buildPacket(
      command: AirocOtaConstants.cmdExitBootloader,
      checksumType: checksumType,
    );
  }

  static Uint8List buildSync({required int checksumType}) {
    return buildPacket(
      command: AirocOtaConstants.cmdSync,
      checksumType: checksumType,
    );
  }

  static AirocOtaResponse parseResponse(Uint8List packet,
      {int? checksumType}) {
    if (packet.length < AirocOtaConstants.basePacketSize) {
      throw const AirocOtaProtocolException('Response packet is too short.');
    }
    if (packet.first != AirocOtaConstants.packetStart) {
      throw const AirocOtaProtocolException('Invalid response start byte.');
    }
    if (packet.last != AirocOtaConstants.packetEnd) {
      throw const AirocOtaProtocolException('Invalid response end byte.');
    }

    final payloadLength = uint16Le(packet, AirocOtaConstants.responseLengthOffset);
    final expectedLength = AirocOtaConstants.basePacketSize + payloadLength;
    if (packet.length != expectedLength) {
      throw AirocOtaProtocolException(
        'Response length mismatch. Expected $expectedLength, got ${packet.length}.',
      );
    }

    if (checksumType != null) {
      final expectedChecksum = uint16Le(packet, packet.length - 3);
      final actualChecksum = calculatePacketChecksum(
        checksumType: checksumType,
        bytes: packet,
        length: packet.length - 3,
      );
      if (expectedChecksum != actualChecksum) {
        throw AirocOtaProtocolException(
          'Checksum mismatch. Expected 0x${expectedChecksum.toRadixString(16)}, '
          'got 0x${actualChecksum.toRadixString(16)}.',
        );
      }
    }

    return AirocOtaResponse(
      statusCode: packet[AirocOtaConstants.responseStatusOffset],
      payload: Uint8List.fromList(
        packet.sublist(
          AirocOtaConstants.responseDataOffset,
          AirocOtaConstants.responseDataOffset + payloadLength,
        ),
      ),
    );
  }

  static EnterBootloaderResponse parseEnterBootloaderPayload(Uint8List payload) {
    if (payload.length < 8) {
      throw const AirocOtaProtocolException(
        'ENTER_BOOTLOADER payload must be at least 8 bytes.',
      );
    }
    return EnterBootloaderResponse(
      siliconId: uint32FromLeBytes(payload, 0),
      siliconRev: payload[4],
      bootloaderVersion: Uint8List.fromList(payload.sublist(5, 8)),
    );
  }

  static int deriveChunkSize({required int mtu}) {
    final mtuLimitedSize = (mtu - 10).clamp(1, AirocOtaConstants.defaultChunkSize);
    return mtuLimitedSize;
  }

  static int calculatePacketChecksum({
    required int checksumType,
    required Uint8List bytes,
    required int length,
  }) {
    if (checksumType == AirocOtaConstants.crcChecksum) {
      return crc16(bytes, length);
    }
    var sum = 0;
    for (var i = length - 1; i >= 0; i--) {
      sum += bytes[i] & 0xFF;
    }
    return (1 + (~sum)) & 0xFFFF;
  }

  static int crc16(Uint8List data, int length) {
    var crc = 0xFFFF;
    if (length == 0) {
      return (~crc) & 0xFFFF;
    }

    for (var h = 0; h < length; h++) {
      var tmp = data[h] & 0xFF;
      for (var i = 0; i < 8; i++, tmp >>= 1) {
        if (((crc & 0x0001) ^ (tmp & 0x0001)) > 0) {
          crc = (crc >> 1) ^ 0x8408;
        } else {
          crc >>= 1;
        }
      }
    }

    crc = ~crc;
    final tmp = crc;
    crc = (crc << 8) | ((tmp >> 8) & 0xFF);
    return crc & 0xFFFF;
  }

  static int crc32(Uint8List data) {
    const g0 = 0x82F63B78;
    const g1 = 0x417B1DBC;
    const g2 = 0x20BD8EDE;
    const g3 = 0x105EC76F;
    const table = <int>[
      0,
      g3,
      g2,
      g2 ^ g3,
      g1,
      g1 ^ g3,
      g1 ^ g2,
      g1 ^ g2 ^ g3,
      g0,
      g0 ^ g3,
      g0 ^ g2,
      g0 ^ g2 ^ g3,
      g0 ^ g1,
      g0 ^ g1 ^ g3,
      g0 ^ g1 ^ g2,
      g0 ^ g1 ^ g2 ^ g3,
    ];

    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte & 0xFF;
      for (var i = 1; i >= 0; i--) {
        crc = (crc >> 4) ^ table[crc & 0x0F];
      }
    }
    return (~crc) & 0xFFFFFFFF;
  }

  static List<int> uint32ToLeBytes(int value) => <int>[
        value & 0xFF,
        (value >> 8) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 24) & 0xFF,
      ];

  static int uint16Le(Uint8List bytes, int offset) =>
      (bytes[offset] & 0xFF) | ((bytes[offset + 1] & 0xFF) << 8);

  static int uint32FromLeBytes(Uint8List bytes, int offset) =>
      (bytes[offset] & 0xFF) |
      ((bytes[offset + 1] & 0xFF) << 8) |
      ((bytes[offset + 2] & 0xFF) << 16) |
      ((bytes[offset + 3] & 0xFF) << 24);
}


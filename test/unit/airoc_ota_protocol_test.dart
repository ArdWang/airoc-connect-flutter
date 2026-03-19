import 'dart:typed_data';

import 'package:airoc_connect_flutter/airoc_connect_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AirocOtaProtocol', () {
    test('buildEnterBootloader creates a framed packet', () {
      final packet = AirocOtaProtocol.buildEnterBootloader(
        productId: 0x11223344,
        checksumType: AirocOtaConstants.sumChecksum,
      );

      expect(packet.first, AirocOtaConstants.packetStart);
      expect(packet.last, AirocOtaConstants.packetEnd);
      expect(packet[1], AirocOtaConstants.cmdEnterBootloader);
      expect(packet[2], 6);
    });

    test('parseResponse reads status and payload', () {
      final packet = AirocOtaProtocol.buildPacket(
        command: AirocOtaConstants.cmdVerifyApp,
        checksumType: AirocOtaConstants.sumChecksum,
        payload: const <int>[1],
      );
      packet[1] = AirocOtaConstants.statusSuccess;

      final response = AirocOtaProtocol.parseResponse(packet);

      expect(response.statusCode, AirocOtaConstants.statusSuccess);
      expect(response.payload, Uint8List.fromList([1]));
    });

    test('deriveChunkSize respects default upper bound', () {
      expect(AirocOtaProtocol.deriveChunkSize(mtu: 23), 13);
      expect(
        AirocOtaProtocol.deriveChunkSize(mtu: 512),
        AirocOtaConstants.defaultChunkSize,
      );
    });
  });
}


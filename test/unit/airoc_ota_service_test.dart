import 'package:airoc_connect_flutter/airoc_connect_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_ota_transport.dart';

void main() {
  group('AirocOtaService', () {
    test('completes a successful OTA session', () async {
      final transport = FakeOtaTransport(
        siliconId: 0x01020304,
        siliconRev: 0x05,
      );
      final service = AirocOtaService(transport: transport);
      final file = Cyacd2Parser.parseString(
        '''
01040302010500010D0C0B0A
@APPINFO:0x1000,0x04
:00100000AABBCCDD
''',
      );

      final progressEvents = <OtaProgress>[];
      final result = await service.performOta(
        file,
        onProgress: progressEvents.add,
      );

      expect(result.success, isTrue);
      expect(result.status, OtaStatus.success);
      expect(progressEvents.any((p) => p.status == OtaStatus.verifying), isTrue);
      expect(transport.writes, isNotEmpty);

      await service.dispose();
      await transport.dispose();
    });

    test('fails when silicon id does not match', () async {
      final transport = FakeOtaTransport(
        siliconId: 0x99999999,
        siliconRev: 0x05,
      );
      final service = AirocOtaService(transport: transport);
      final file = Cyacd2Parser.parseString(
        '''
01040302010500010D0C0B0A
@APPINFO:0x1000,0x04
:00100000AABBCCDD
''',
      );

      final result = await service.performOta(file);

      expect(result.success, isFalse);
      expect(result.status, OtaStatus.failed);
      expect(result.errorMessage, contains('silicon mismatch'));

      await service.dispose();
      await transport.dispose();
    });

    test('falls back to PROGRAM_ROW when PROGRAM_DATA is unsupported', () async {
      final transport = FakeOtaTransport(
        siliconId: 0x11223344,
        siliconRev: 0x01,
        rejectProgramData: true,
      );
      final service = AirocOtaService(transport: transport);
      final file = CyacdParser.parseString(
        '''
112233440100
:0100020004AABBCCDDFF
''',
      );

      final result = await service.performOta(file);

      expect(result.success, isTrue);
      expect(
        transport.writes.any((p) => p[1] == AirocOtaConstants.cmdProgramData),
        isTrue,
      );
      expect(
        transport.writes.any((p) => p[1] == AirocOtaConstants.cmdProgramRow),
        isTrue,
      );

      await service.dispose();
      await transport.dispose();
    });

    test('retries VERIFY_APP on CYRET_ERR_DATA and succeeds', () async {
      final transport = FakeOtaTransport(
        siliconId: 0x01020304,
        siliconRev: 0x05,
        verifyStatusSequence: <int>[
          AirocOtaConstants.statusErrData,
          AirocOtaConstants.statusSuccess,
        ],
      );
      final service = AirocOtaService(transport: transport);
      final file = Cyacd2Parser.parseString(
        '''
01040302010500010D0C0B0A
@APPINFO:0x1000,0x04
:00100000AABBCCDD
''',
      );

      final result = await service.performOta(file);

      expect(result.success, isTrue);
      expect(result.status, OtaStatus.success);
      expect(
        transport.writes.where((p) => p[1] == AirocOtaConstants.cmdVerifyApp),
        hasLength(2),
      );

      await service.dispose();
      await transport.dispose();
    });

    test('falls back to payload-less VERIFY_APP variant', () async {
      final transport = FakeOtaTransport(
        siliconId: 0x01020304,
        siliconRev: 0x05,
        verifyRequiresNoPayload: true,
      );
      final service = AirocOtaService(transport: transport);
      final file = Cyacd2Parser.parseString(
        '''
01040302010500010D0C0B0A
@APPINFO:0x1000,0x04
:00100000AABBCCDD
''',
      );

      final result = await service.performOta(file);

      expect(result.success, isTrue);
      expect(result.status, OtaStatus.success);
      // Must attempt VERIFY_APP at least twice: payloaded first, no-payload fallback.
      expect(
        transport.writes.where((p) => p[1] == AirocOtaConstants.cmdVerifyApp).length,
        greaterThanOrEqualTo(2),
      );

      await service.dispose();
      await transport.dispose();
    });
  });
}


import 'dart:typed_data';

import 'package:airoc_connect_flutter/airoc_connect_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CyacdParser', () {
    test('parses legacy CYACD header and data rows', () {
      const content = '''
112233440100
:0100020004AABBCCDDFF
''';

      final file = CyacdParser.parseString(content, fileName: 'test.cyacd');

      expect(file.fileType, OtaFileType.cyacd);
      expect(file.siliconId, 0x11223344);
      expect(file.siliconRev, 0x01);
      expect(file.checksumType, 0x00);
      expect(file.rows, hasLength(1));
      expect(file.rows.first.isData, isTrue);
      expect(file.rows.first.address, 0x010002);
      expect(file.rows.first.data, Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD]));
    });

    test('accepts CYACD2-like payload saved as .cyacd', () {
      const content = '''
01040302010500010D0C0B0A
@APPINFO:0x1000,0x20
:00100000AABBCCDD
''';

      final file = CyacdParser.parseString(content, fileName: 'test.cyacd');

      expect(file.fileType, OtaFileType.cyacd);
      expect(file.appStart, 0x1000);
      expect(file.rows.last.data, Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD]));
    });

    test('rejects empty file', () {
      expect(
        () => CyacdParser.parseString(''),
        throwsA(isA<CyacdParseException>()),
      );
    });
  });
}


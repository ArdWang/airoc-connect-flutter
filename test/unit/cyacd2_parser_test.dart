import 'dart:typed_data';

import 'package:airoc_connect_flutter/airoc_connect_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Cyacd2Parser', () {
    test('parses header, app info, eiv, and data rows', () {
      const content = '''
01040302010500010D0C0B0A
@APPINFO:0x1000,0x20
@EIV:11223344
:00100000AABBCCDD
''';

      final file = Cyacd2Parser.parseString(content, fileName: 'test.cyacd2');

      expect(file.fileType, OtaFileType.cyacd2);
      expect(file.firmwareVersion, 1);
      expect(file.siliconId, 0x01020304);
      expect(file.siliconRev, 0x05);
      expect(file.checksumType, 0x00);
      expect(file.appId, 0x01);
      expect(file.productId, 0x0A0B0C0D);
      expect(file.appStart, 0x1000);
      expect(file.appSize, 0x20);
      expect(file.rows, hasLength(2));
      expect(file.rows.first.isEiv, isTrue);
      expect(file.rows.last.isData, isTrue);
      expect(file.rows.last.address, 0x1000);
      expect(file.rows.last.data, Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD]));
    });

    test('rejects empty file', () {
      expect(
        () => Cyacd2Parser.parseString(''),
        throwsA(isA<Cyacd2ParseException>()),
      );
    });
  });
}


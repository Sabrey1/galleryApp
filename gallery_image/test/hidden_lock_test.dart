import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gallery_image/screens/hidden_unlock_screen.dart';

void main() {
  test('lock derivation matches PBKDF2-HMAC-SHA256', () {
    final salt = base64Encode(utf8.encode('salt'));
    expect(
      deriveHiddenLock(['1234', salt]),
      'df8GTaof4QWublMygetGHORSTASm5weq0fDTQsXHI3c=',
    );
    expect(deriveHiddenLock(['1235', salt]), isNot(deriveHiddenLock(['1234', salt])));
  });
}

import 'package:shutter/src/dart_literal.dart';
import 'package:test/test.dart';

void main() {
  test('escapes backslashes, quotes, interpolation, and newlines', () {
    expect(dartString('plain'), "'plain'");
    expect(
      dartString(
        r"a\b'c$d"
        '\n\r',
      ),
      r"'a\\b\'c\$d\n\r'",
    );
  });
}

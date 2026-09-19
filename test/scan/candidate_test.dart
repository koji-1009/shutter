import 'package:shutter/src/scan/candidate.dart';
import 'package:test/test.dart';

void main() {
  test('static id is the first 16 hex of sha256(file|symbol|index)', () {
    // Ids pair shots across runs, so the formula must not drift.
    expect(shotStaticId('lib/a.dart', 'a', 0), 'e815cfe43338aced');
  });
}

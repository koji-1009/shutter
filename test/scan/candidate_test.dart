import 'package:shutter/src/scan/candidate.dart';
import 'package:test/test.dart';

void main() {
  test('static id is the first 16 hex of sha256(file|symbol|index)', () {
    // Ids pair shots across runs, so the formula must not drift.
    final candidate = Candidate(
      file: 'lib/a.dart',
      line: 1,
      column: 1,
      symbol: 'a',
      annotationIndex: 0,
      annotation: '',
      target: '',
    );
    expect(candidate.staticId, 'e815cfe43338aced');
  });
}

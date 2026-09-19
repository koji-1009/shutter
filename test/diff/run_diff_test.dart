import 'package:shutter/src/diff/run_diff.dart';
import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';

void main() {
  RunDiff diff(List<DiffStatus> statuses) => RunDiff(
    before: '/r',
    after: '/s',
    entries: [
      for (final (i, s) in statuses.indexed)
        DiffEntry(
          status: s,
          shot: Shot(id: '$i', status: ShotStatus.ok, name: '$i'),
        ),
    ],
  );

  test('exit code: 0 unchanged, 1 differences', () {
    expect(diff([]).exitCode, 0);
    expect(diff([DiffStatus.unchanged]).exitCode, 0);
    expect(diff([DiffStatus.unchanged, DiffStatus.added]).exitCode, 1);
  });
}

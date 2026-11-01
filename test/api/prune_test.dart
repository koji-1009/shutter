import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shutter/shutter.dart';
import 'package:shutter/src/project/project.dart';
import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('prune keeps the newest runs of the project at or above the '
      'directory', () {
    final root = createProject();
    final runs = Project.load(root).runsDir;
    for (final id in ['20260918T101530Z', '20260918T101531Z']) {
      final dir = p.join(runs, id);
      Directory(dir).createSync(recursive: true);
      RunManifest(run: id, shots: const []).write(dir);
    }
    final result = prune(p.join(root, 'lib'), keep: 1);
    expect(result.removed, [p.join(runs, '20260918T101530Z')]);
    expect(result.kept, [p.join(runs, '20260918T101531Z')]);
    expect(Directory(result.removed.single).existsSync(), isFalse);
  });

  test('a negative keep, or no project, throws', () {
    expect(
      () => prune(createProject(), keep: -1),
      throwsA(
        isA<ShutterException>()
            .having((e) => e.exitCode, 'exitCode', 64)
            .having(
              (e) => e.message,
              'message',
              'keep must not be negative (-1).',
            ),
      ),
    );
    expect(
      () => prune(tempDir(), keep: 0),
      throwsA(
        isA<ShutterException>().having((e) => e.exitCode, 'exitCode', 78),
      ),
    );
  });
}

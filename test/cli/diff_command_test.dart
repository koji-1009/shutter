import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shutter/src/project/project.dart';
import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../run/run_store_test.dart' show writeRun;
import 'fakes.dart';

void main() {
  late String root;

  setUp(() {
    root = createProject();
    final project = Project.load(root);
    writeRun(
      project,
      'r1',
      shots: const [
        Shot(id: 'a.0', status: ShotStatus.ok, name: 'A', png: 'a.0.png'),
      ],
    );
    writeRun(
      project,
      'r2',
      shots: const [
        Shot(id: 'a.0', status: ShotStatus.ok, name: 'A', png: 'a.0.png'),
      ],
    );
    File(p.join(project.runsDir, 'r1', 'a.0.png')).writeAsBytesSync(png(2, 2));
    File(p.join(project.runsDir, 'r2', 'a.0.png'))
        .writeAsBytesSync(png(2, 2, [255, 255, 255, 255]));
  });

  test('diff exits 1 on changes and writes nothing without --images', () async {
    final result = await runCli(['diff', 'r1', 'r2'], fakeContext(root));
    expect(result.exitCode, 1, reason: result.stderr);
    expect(result.stdout, contains('status: changed'));
    expect(result.stdout, isNot(contains('diff:')));
    expect(
      Directory(p.join(root, '.dart_tool', 'shutter', 'diffs')).existsSync(),
      isFalse,
    );
  });

  test(
    '--images writes the diff image under .dart_tool/shutter/diffs/',
    () async {
      final result = await runCli([
        'diff',
        'r1',
        'r2',
        '--images',
      ], fakeContext(root));
      expect(result.exitCode, 1, reason: result.stderr);
      final diffDir = p.join(
        root,
        '.dart_tool',
        'shutter',
        'diffs',
        '20260918T101530Z',
      );
      expect(result.stdout, contains('diff: $diffDir\n'));
      expect(File(p.join(diffDir, 'a.0.png')).existsSync(), isTrue);
    },
  );

  test('anything but two runs is a usage error', () async {
    for (final args in [
      <String>[],
      ['r1'],
      ['r1', 'r2', 'r3'],
    ]) {
      final result = await runCli(['diff', ...args], fakeContext(root));
      expect(result.exitCode, 64, reason: '$args');
      expect(result.stderr, contains('expected two runs: <run-a> <run-b>.'));
    }
  });

  test('a missing run is missing input', () async {
    final result = await runCli(['diff', 'r1', 'zz'], fakeContext(root));
    expect(result.exitCode, 66);
    expect(result.stderr, contains('no run "zz"'));
  });
}

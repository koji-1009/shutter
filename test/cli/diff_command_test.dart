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

  test('--composite writes one sheet per entry that has something to '
      'show', () async {
    final result = await runCli([
      'diff',
      'r1',
      'r2',
      '--composite',
      '--direction',
      'vertical',
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
    expect(result.stdout, contains('composite: ${p.join(diffDir, 'a.0')}'));
    expect(File(p.join(diffDir, 'a.0-composite.png')).existsSync(), isTrue);
    // The marked image is the composite's middle panel, not a file.
    expect(File(p.join(diffDir, 'a.0.png')).existsSync(), isFalse);
  });

  test('--direction and --title need --composite', () async {
    for (final args in [
      ['--direction', 'vertical'],
      ['--title', 'x'],
    ]) {
      final result = await runCli([
        'diff',
        'r1',
        'r2',
        ...args,
      ], fakeContext(root));
      expect(result.exitCode, 64, reason: '$args');
      expect(
        result.stderr,
        contains('--direction and --title need --composite.'),
      );
    }
  });

  test('--title renders the text and draws it on every sheet', () async {
    final engine = FakeEngine(const [
      Shot(id: 't.0', status: ShotStatus.ok, name: 'title', png: 't.0.png'),
    ]);
    final result = await runCli([
      'diff',
      'r1',
      'r2',
      '--composite',
      '--title',
      '検索フィールド',
    ], fakeContext(root, engine: engine));
    expect(result.exitCode, 1, reason: result.stderr);
    final request = engine.requests.single;
    expect(request.libraries, isEmpty);
    expect(request.shell, isNull);
    final widget = request.widget!;
    expect(widget.source, contains(r"Text('検索フィールド'"));
    // The size the narrowest sheet's captions read at.
    expect(widget.source, contains('fontSize: 11.0'));
    // Half the room between the narrowest sheet's gutters, in logical
    // pixels, and as many lines as the text needs.
    expect(widget.size, (19.0, double.infinity));
    expect(widget.helperSource(), contains('double.infinity'));
    // The scratch directory the title was shot into does not survive.
    expect(
      Directory(p.join(root, '.dart_tool', 'shutter', 'diffs'))
          .listSync()
          .map((e) => p.basename(e.path)),
      isNot(contains(endsWith('-title'))),
    );
  });

  test('a title that took more than one line says so', () async {
    final engine = FakeEngine(
      const [
        Shot(id: 't.0', status: ShotStatus.ok, name: 'title', png: 't.0.png'),
      ],
      // Taller than the one line the 38px sheets have room for.
      bytes: png(38, 60, [0, 0, 0, 255]),
    );
    final result = await runCli([
      'diff',
      'r1',
      'r2',
      '--composite',
      '--title',
      'a title with rather a lot of words in it',
    ], fakeContext(root, engine: engine));
    expect(result.exitCode, 1);
    expect(
      result.stderr,
      contains('--title does not fit one line on the 38px sheets'),
    );
  });

  test('a title that could not be drawn leaves the sheets untitled', () async {
    final engine = FakeEngine(const [
      Shot(id: 't.0', status: ShotStatus.error, name: 'title', error: 'boom'),
    ]);
    final result = await runCli([
      'diff',
      'r1',
      'r2',
      '--composite',
      '--title',
      'x',
    ], fakeContext(root, engine: engine));
    expect(result.exitCode, 1);
    expect(
      result.stderr,
      contains('--title was not drawn for the 38px sheets: boom'),
    );
    final diffDir = p.join(
      root,
      '.dart_tool',
      'shutter',
      'diffs',
      '20260918T101530Z',
    );
    expect(File(p.join(diffDir, 'a.0-composite.png')).existsSync(), isTrue);
  });

  test('runs with nothing to show need no title and no SDK', () async {
    final project = Project.load(root);
    for (final id in ['r1', 'r2']) {
      File(p.join(project.runsDir, id, 'a.0.png'))
          .writeAsBytesSync(png(2, 2, [1, 2, 3, 255]));
    }
    final engine = FakeEngine(const []);
    final result = await runCli([
      'diff',
      'r1',
      'r2',
      '--composite',
      '--title',
      'x',
    ], fakeContext(root, engine: engine, environment: const {}));
    expect(result.exitCode, 0, reason: result.stderr);
    expect(engine.requests, isEmpty);
    expect(result.stdout, isNot(contains('composite:')));
  });

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

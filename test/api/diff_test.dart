import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shutter/shutter.dart';
import 'package:shutter/src/api/compare.dart';
import 'package:shutter/src/api/diff.dart' show shotDiff;
import 'package:shutter/src/project/project.dart';
import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';

import '../cli/fakes.dart';
import '../helpers.dart';

void main() {
  late String root;
  late Project project;

  /// Writes run [id] holding [shots], each PNG filled with [rgba].
  String writeRun(
    String id,
    List<Shot> shots, {
    List<int> rgba = const [0, 0, 0, 255],
    ShellFile? shell,
    RunSetup setup = plainSetup,
  }) {
    final dir = p.join(project.runsDir, id);
    Directory(dir).createSync(recursive: true);
    RunManifest(run: id, shots: shots, shell: shell, setup: setup).write(dir);
    for (final shot in shots) {
      if (shot.png case final name?) {
        File(p.join(dir, name)).writeAsBytesSync(png(2, 2, rgba));
      }
    }
    return dir;
  }

  setUp(() {
    root = createProject();
    project = Project.load(root);
  });

  test('compares two runs by shot id, with absolute paths and what each '
      'was shot with', () async {
    const a = Shot(
      id: 'a.0',
      status: ShotStatus.ok,
      name: 'a',
      file: 'lib/a.dart',
      line: 1,
      size: (2, 2),
      png: 'a.0.png',
    );
    const gone = Shot(
      id: 'g.0',
      status: ShotStatus.ok,
      name: 'g',
      png: 'g.0.png',
    );
    const added = Shot(
      id: 'n.0',
      status: ShotStatus.error,
      name: 'n',
      error: 'boom',
    );
    final before = writeRun('r1', const [a, gone]);
    final after = writeRun(
      'r2',
      [
        const Shot(
          id: 'a.0',
          status: ShotStatus.ok,
          name: 'a',
          file: 'lib/a.dart',
          line: 1,
          size: (3, 2),
          png: 'a.0.png',
        ),
        added,
      ],
      rgba: [255, 255, 255, 255],
      shell: (path: 'lib/preview/shell.dart', sha256: 'abc'),
      setup: (
        actions: ['tap text:Open'],
        screen: true,
        viewport: (390, 844),
        keyboard: 336,
        keyboardTint: 0xFF9E9E9E,
        networkImages: {
          'https://example.com/a.png': (path: 'test/a.png', sha256: 'def'),
        },
        semantics: true,
        platform: ShotPlatform.ios,
        pixelRatio: 3,
        safeArea: (59, 34),
        brightness: ShotBrightness.dark,
        textScale: 1.3,
        locale: 'ja-JP',
      ),
    );

    final result = await diff(root, 'r1', p.relative(after, from: root));
    expect(
      result,
      ShotDiff(
        before: before,
        after: after,
        beforeSetup: const ShotSetup(),
        afterSetup: const ShotSetup(
          shell: ShotFile(path: 'lib/preview/shell.dart', sha256: 'abc'),
          actions: ['tap text:Open'],
          capture: ScreenCapture(viewport: LogicalSize(390, 844)),
          keyboard: Keyboard(336, tint: 0xFF9E9E9E),
          networkImages: {
            'https://example.com/a.png': ShotFile(
              path: 'test/a.png',
              sha256: 'def',
            ),
          },
          semantics: true,
          platform: ShotPlatform.ios,
          pixelRatio: 3,
          safeArea: SafeAreaInsets(top: 59, bottom: 34),
          brightness: ShotBrightness.dark,
          textScale: 1.3,
          locale: 'ja-JP',
        ),
        entries: [
          ShotDiffEntry(
            status: DiffStatus.changed,
            shot: ShotResult(
              id: 'a.0',
              status: ShotStatus.ok,
              name: 'a',
              file: 'lib/a.dart',
              line: 1,
              size: const LogicalSize(3, 2),
              png: p.join(after, 'a.0.png'),
            ),
            diffRatio: 1,
            beforeSize: const LogicalSize(2, 2),
            beforePng: p.join(before, 'a.0.png'),
            afterPng: p.join(after, 'a.0.png'),
          ),
          const ShotDiffEntry(
            status: DiffStatus.added,
            shot: ShotResult(
              id: 'n.0',
              status: ShotStatus.error,
              name: 'n',
              error: 'boom',
            ),
          ),
          ShotDiffEntry(
            status: DiffStatus.removed,
            shot: ShotResult(
              id: 'g.0',
              status: ShotStatus.ok,
              name: 'g',
              png: p.join(before, 'g.0.png'),
            ),
            beforePng: p.join(before, 'g.0.png'),
          ),
        ],
      ),
    );
    expect(result.hasChanges, isTrue);
    expect(
      Directory(p.join(root, '.dart_tool', 'shutter', 'diffs')).existsSync(),
      isFalse,
    );

    final same = await diff(root, 'r1', 'r1');
    expect(same.entries.map((e) => e.status), [
      DiffStatus.unchanged,
      DiffStatus.unchanged,
    ]);
    expect(same.hasChanges, isFalse);
  });

  test('images and sheets go into a new diffs directory', () async {
    const a = Shot(id: 'a.0', status: ShotStatus.ok, name: 'a', png: 'a.0.png');
    writeRun('r1', const [a]);
    writeRun('r2', const [a], rgba: [255, 255, 255, 255]);
    final result = await diff(
      root,
      'r1',
      'latest',
      images: true,
      composite: const DiffComposite(direction: CompositeDirection.vertical),
    );
    final dir = result.dir!;
    expect(p.dirname(dir), p.join(root, '.dart_tool', 'shutter', 'diffs'));
    final entry = result.entries.single;
    expect(entry.diffPng, p.join(dir, 'a.0.png'));
    expect(entry.compositePng, p.join(dir, 'a.0-composite.png'));
    expect(File(entry.diffPng!).existsSync(), isTrue);
    expect(File(entry.compositePng!).existsSync(), isTrue);
  });

  test('a title that could not be drawn is a warning, not an error', () async {
    const a = Shot(id: 'a.0', status: ShotStatus.ok, name: 'a', png: 'a.0.png');
    writeRun('r1', const [a]);
    writeRun('r2', const [a], rgba: [255, 255, 255, 255]);
    final engine = FakeEngine(const [
      Shot(id: 't.0', status: ShotStatus.error, name: 'title', error: 'boom'),
    ]);
    final result = shotDiff(
      await compare(
        fakeContext(root, engine: engine),
        'r1',
        'r2',
        composite: const DiffComposite(title: 'x'),
      ),
    );
    expect(result.warnings, [
      'The title was not drawn for the 38px sheets: boom',
    ]);
    expect(File(result.entries.single.compositePng!).existsSync(), isTrue);
  });

  test('a run that is not found throws', () async {
    await expectLater(
      diff(root, 'r1', 'r2'),
      throwsA(
        isA<ShutterException>().having((e) => e.exitCode, 'exitCode', 66),
      ),
    );
  });
}

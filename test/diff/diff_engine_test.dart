import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shutter/src/diff/diff_engine.dart';
import 'package:shutter/src/diff/run_diff.dart';
import 'package:shutter/src/run/manifest.dart';
import 'package:shutter/src/run/run_store.dart';
import 'package:test/test.dart';

import '../helpers.dart';

StoredRun run(String name, List<Shot> shots, Map<String, List<int>> pngs) {
  final dir = p.join(tempDir(), name);
  Directory(dir).createSync();
  for (final MapEntry(:key, :value) in pngs.entries) {
    File(p.join(dir, key)).writeAsBytesSync(value);
  }
  final manifest = RunManifest(run: name, shots: shots)..write(dir);
  return StoredRun(dir, manifest);
}

Shot ok(String id, {String? file, int? line, (double, double) size = (1, 1)}) =>
    Shot(
      id: id,
      status: ShotStatus.ok,
      png: '$id.png',
      name: id,
      file: file,
      line: line,
      size: size,
    );

void main() {
  test("carries each run's shell and setup", () {
    final dir = p.join(tempDir(), 'pressed');
    Directory(dir).createSync();
    final pressed = StoredRun(
      dir,
      const RunManifest(
        run: 'pressed',
        shots: [],
        shell: (path: 'lib/preview/shell.dart', sha256: '1f2e'),
        actions: ['press text:OK'],
        screen: true,
        viewport: (390, 844),
      )..write(dir),
    );
    final diff = diffRuns(run('plain', const [], const {}), pressed);
    expect(diff.beforeShell, isNull);
    expect(diff.afterShell?.path, 'lib/preview/shell.dart');
    expect(diff.beforeSetup.actions, isEmpty);
    expect(diff.afterSetup.actions, ['press text:OK']);
    expect(
      (diff.afterSetup.screen, diff.afterSetup.viewport),
      (true, (390.0, 844.0)),
    );
  });

  test('classifies every id; --images writes diff images', () {
    final black = png(4, 4);
    final white = png(4, 4, [255, 255, 255, 255]);
    final tall = png(4, 5);
    final a = run(
      'a',
      [
        ok('same', file: 'lib/b.dart', line: 2),
        ok('same2', file: 'lib/b.dart', line: 2),
        ok('same3', file: 'lib/a.dart', line: 9),
        ok('changed'),
        ok('resized'),
        ok('removed'),
        const Shot(
          id: 'err',
          status: ShotStatus.error,
          name: 'err',
          error: 'old',
        ),
        ok('broke'),
        const Shot(id: 'nopng', status: ShotStatus.ok, name: 'nopng'),
        const Shot(
          id: 'stuck',
          status: ShotStatus.error,
          name: 'stuck',
          png: 'stuck.png',
          error: 'same',
          at: 'lib/x.dart:1:2',
        ),
        const Shot(
          id: 'worse',
          status: ShotStatus.error,
          name: 'worse',
          error: 'overflow 1',
        ),
      ],
      {
        'same.png': black,
        'same2.png': black,
        'same3.png': black,
        'changed.png': black,
        'resized.png': black,
        'removed.png': black,
        'broke.png': black,
        'stuck.png': black,
      },
    );
    final b = run(
      'b',
      [
        ok('same', file: 'lib/b.dart', line: 2),
        ok('same2', file: 'lib/b.dart', line: 2),
        ok('same3', file: 'lib/a.dart', line: 9),
        ok('changed'),
        ok('resized', size: (1, 1.25)),
        ok('added'),
        const Shot(
          id: 'err',
          status: ShotStatus.ok,
          name: 'err',
          png: 'err.png',
        ),
        const Shot(
          id: 'broke',
          status: ShotStatus.error,
          name: 'broke',
          png: 'broke.png',
          error: 'new',
          at: 'lib/x.dart:1:2',
        ),
        const Shot(
          id: 'nopng',
          status: ShotStatus.ok,
          name: 'nopng',
          png: 'nopng.png',
        ),
        const Shot(
          id: 'stuck',
          status: ShotStatus.error,
          name: 'stuck',
          png: 'stuck.png',
          error: 'same',
          at: 'lib/x.dart:1:2',
        ),
        const Shot(
          id: 'worse',
          status: ShotStatus.error,
          name: 'worse',
          error: 'overflow 2',
        ),
      ],
      {
        'same.png': black,
        'same2.png': black,
        'same3.png': black,
        'changed.png': white,
        'resized.png': tall,
        'added.png': black,
        'err.png': black,
        'broke.png': black,
        'nopng.png': black,
        'stuck.png': black,
      },
    );
    final diff = diffRuns(a, b);
    final statuses = {for (final e in diff.entries) e.shot.id: e.status};
    expect(statuses, {
      'broke': DiffStatus.changed,
      'err': DiffStatus.changed,
      'worse': DiffStatus.changed,
      'stuck': DiffStatus.unchanged,
      'changed': DiffStatus.changed,
      'nopng': DiffStatus.changed,
      'resized': DiffStatus.changed,
      'added': DiffStatus.added,
      'removed': DiffStatus.removed,
      'same3': DiffStatus.unchanged,
      'same': DiffStatus.unchanged,
      'same2': DiffStatus.unchanged,
    });
    expect(diff.entries.map((e) => e.shot.id).toList(), [
      'broke',
      'changed',
      'err',
      'nopng',
      'resized',
      'worse',
      'added',
      'removed',
      'stuck',
      'same3',
      'same',
      'same2',
    ]);
    final broke = diff.entries.singleWhere((e) => e.shot.id == 'broke');
    expect(broke.shot.error, 'new');
    expect(broke.shot.at, 'lib/x.dart:1:2');
    final fixed = diff.entries.singleWhere((e) => e.shot.id == 'err');
    expect(fixed.shot.error, isNull);
    final changed = diff.entries.singleWhere((e) => e.shot.id == 'changed');
    expect(changed.diffRatio, 1);
    expect(changed.shot.name, 'changed');
    expect(changed.beforePng, 'changed.png');
    expect(changed.afterPng, 'changed.png');
    expect(changed.diffPng, isNull);
    // The before size only when it changed.
    expect(changed.beforeSize, isNull);
    final resized = diff.entries.singleWhere((e) => e.shot.id == 'resized');
    expect((resized.shot.size, resized.beforeSize), ((1, 1.25), (1, 1)));
    final added = diff.entries.singleWhere((e) => e.shot.id == 'added');
    expect([added.beforePng, added.afterPng], [null, 'added.png']);
    expect(added.diffRatio, isNull);
    final removed = diff.entries.singleWhere((e) => e.shot.id == 'removed');
    expect([removed.beforePng, removed.afterPng], ['removed.png', null]);
    expect(removed.shot.png, 'removed.png');
    final same = diff.entries.singleWhere((e) => e.shot.id == 'same');
    expect(same.diffRatio, 0);

    // With images: a diff image for each changed entry that has both
    // sides' pixels.
    final withImages = tempDir();
    final imaged = diffRuns(a, b, imagesDir: withImages);
    expect(
      {
        for (final e in imaged.entries)
          if (e.diffPng != null) e.shot.id,
      },
      {'changed', 'resized'},
    );
    expect(File(p.join(withImages, 'changed.png')).existsSync(), isTrue);
    expect((diff.before, diff.after), (a.dir, b.dir));
    expect(diff.exitCode, 1);
  });

  test('a PNG named in the manifest but missing on disk is no image', () {
    final a = run('a', [ok('x')], {'x.png': png(2, 2)});
    final b = run('b', [ok('x')], {});
    final entry = diffRuns(a, b).entries.single;
    expect(entry.status, DiffStatus.changed);
    expect(entry.diffRatio, isNull);
  });

  test('one differing pixel is a change', () {
    final pixel = img.Image(width: 100, height: 100, numChannels: 4);
    img.fill(pixel, color: img.ColorRgba8(0, 0, 0, 255));
    pixel.setPixelRgba(5, 5, 255, 0, 0, 255);
    final a = run('a', [ok('x')], {'x.png': png(100, 100)});
    final b = run('b', [ok('x')], {'x.png': img.encodePng(pixel)});
    final diff = diffRuns(a, b);
    expect(diff.entries.single.status, DiffStatus.changed);
    expect(diff.entries.single.diffRatio, 0.0001);
  });
}

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shutter/src/project/project.dart';
import 'package:shutter/src/run/manifest.dart';
import 'package:shutter/src/run/run_store.dart';
import 'package:shutter/src/run/timestamp_id.dart';
import 'package:shutter/src/shutter_exception.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void writeRun(Project project, String id, {List<Shot> shots = const []}) {
  final dir = p.join(project.runsDir, id);
  Directory(dir).createSync(recursive: true);
  RunManifest(run: id, shots: shots).write(dir);
}

void main() {
  test('loadRun resolves ids and run directories; missing runs are '
      'EX_NOINPUT', () {
    final project = Project.load(createProject());
    writeRun(
      project,
      'r1',
      shots: const [
        Shot(id: 'a.0', status: ShotStatus.ok, name: 'a', png: 'a.0.png'),
        Shot(id: 'b.0', status: ShotStatus.error, name: 'b'),
      ],
    );
    StoredRun load(String argument, {String? from}) =>
        loadRun(project, argument, workingDirectory: from ?? project.root);
    final byId = load('r1');
    expect(byId.dir, p.join(project.runsDir, 'r1'));
    expect(byId.pngPath(byId.manifest.shots[0]), p.join(byId.dir, 'a.0.png'));
    expect(byId.pngPath(byId.manifest.shots[1]), isNull);
    expect(load(p.join(project.runsDir, 'r1')).dir, byId.dir);
    // A relative directory is relative to the working directory given,
    // not to the current one.
    expect(
      load(p.join('runs', 'r1'), from: p.dirname(project.runsDir)).dir,
      byId.dir,
    );
    expect(
      () => load('nope'),
      throwsA(isA<ShutterException>().having((e) => e.exitCode, 'code', 66)),
    );
  });

  test('latest and latest~N count back from the newest run by time, then '
      'suffix, skipping runs without a manifest', () {
    final project = Project.load(createProject());
    StoredRun load(String argument) =>
        loadRun(project, argument, workingDirectory: project.root);
    Matcher noInput(String message) => throwsA(
      isA<ShutterException>()
          .having((e) => e.exitCode, 'code', 66)
          .having((e) => e.message, 'message', contains(message)),
    );
    expect(() => load('latest'), noInput('0 runs'));
    for (final id in [
      '20260918T101530Z-10',
      '20260918T101530Z',
      '20260918T101530Z-2',
      '20260917T235959Z',
    ]) {
      writeRun(project, id);
    }
    // Claimed and being shot: no manifest yet.
    Directory(p.join(project.runsDir, '20260918T101531Z'))
        .createSync(recursive: true);
    File(p.join(project.runsDir, '.20260918T101530Z')).createSync();
    String id(String argument) => p.basename(load(argument).dir);
    expect(id('latest'), '20260918T101530Z-10');
    expect(id('latest~0'), '20260918T101530Z-10');
    expect(id('latest~1'), '20260918T101530Z-2');
    expect(id('latest~2'), '20260918T101530Z');
    expect(id('latest~3'), '20260917T235959Z');
    expect(load('latest').dir, p.join(project.runsDir, '20260918T101530Z-10'));
    expect(() => load('latest~4'), noInput('4 runs'));
    expect(() => load('latest~x'), noInput('no run "latest~x"'));
  });

  test('pruneRuns deletes all but the newest runs with their claims, and '
      'leaves a run still being shot', () {
    final project = Project.load(createProject());
    final nothing = pruneRuns(project, 1);
    expect(nothing.removed, isEmpty);
    expect(nothing.kept, isEmpty);
    final ids = [
      '20260917T235959Z',
      '20260918T101530Z',
      '20260918T101530Z-2',
      '20260918T101530Z-10',
    ];
    for (final id in ids) {
      writeRun(project, id);
    }
    // Shot by shutter, so with the file that claimed its id.
    File(p.join(project.runsDir, '.20260917T235959Z')).createSync();
    // Claimed and being shot: no manifest yet.
    final shooting = p.join(project.runsDir, '20260918T101531Z');
    Directory(shooting).createSync(recursive: true);
    File(p.join(project.runsDir, '.20260918T101531Z')).createSync();
    String dir(String id) => p.join(project.runsDir, id);

    final pruned = pruneRuns(project, 2);
    expect(pruned.removed, [dir(ids[0]), dir(ids[1])]);
    expect(pruned.kept, [dir(ids[2]), dir(ids[3])]);
    for (final id in ids.take(2)) {
      expect(Directory(dir(id)).existsSync(), isFalse, reason: id);
    }
    expect(File(dir('.20260917T235959Z')).existsSync(), isFalse);
    expect(Directory(shooting).existsSync(), isTrue);
    expect(File(dir('.20260918T101531Z')).existsSync(), isTrue);
    expect(
      p.basename(
        loadRun(project, 'latest', workingDirectory: project.root).dir,
      ),
      ids[3],
    );

    expect(pruneRuns(project, 5).removed, isEmpty);
    expect(pruneRuns(project, 0).removed, [dir(ids[2]), dir(ids[3])]);
    expect(Directory(shooting).existsSync(), isTrue);
  });

  test('createTimestampDir names directories after UTC time, suffixing '
      'collisions', () {
    final parent = tempDir();
    final now = DateTime.utc(2026, 9, 8, 7, 5, 3);
    final nested = p.join(parent, 'runs');
    String name() => p.basename(createTimestampDir(nested, now));
    expect(name(), '20260908T070503Z');
    expect(name(), '20260908T070503Z-2');
    final path = createTimestampDir(nested, now);
    expect(path, p.join(nested, '20260908T070503Z-3'));
    expect(Directory(path).existsSync(), isTrue);
    // Claimed by another process, directory not yet created.
    File(p.join(nested, '.20260908T070503Z-4')).createSync();
    expect(name(), '20260908T070503Z-5');
    expect(
      p.basename(
        createTimestampDir(
          parent,
          DateTime.utc(2026, 12, 31, 23, 59, 59).toLocal(),
        ),
      ),
      '20261231T235959Z',
    );
  });
}

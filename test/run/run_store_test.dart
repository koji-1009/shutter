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
    final byId = loadRun(project, 'r1');
    expect(byId.dir, p.join(project.runsDir, 'r1'));
    expect(byId.pngPath(byId.manifest.shots[0]), p.join(byId.dir, 'a.0.png'));
    expect(byId.pngPath(byId.manifest.shots[1]), isNull);
    expect(loadRun(project, p.join(project.runsDir, 'r1')).dir, byId.dir);
    expect(
      () => loadRun(project, 'nope'),
      throwsA(isA<ShutterException>().having((e) => e.exitCode, 'code', 66)),
    );
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

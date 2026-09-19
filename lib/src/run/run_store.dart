import 'dart:io';

import 'package:path/path.dart' as p;

import '../project/project.dart';
import '../shutter_exception.dart';
import 'manifest.dart';

/// A run directory on disk.
class StoredRun(
  /// Absolute path of the run directory.
  final String dir,
  final RunManifest manifest,
) {
  /// Absolute path of a shot's PNG, or null when it has none.
  String? pngPath(Shot shot) => shot.png == null ? null : p.join(dir, shot.png);
}

/// Loads the run named by [argument]: a directory containing
/// `manifest.json`, or a run id under `.shutter/runs/`.
StoredRun loadRun(Project project, String argument) {
  for (final candidate in [argument, p.join(project.runsDir, argument)]) {
    if (File(p.join(candidate, manifestFileName)).existsSync()) {
      final dir = p.normalize(p.absolute(candidate));
      return StoredRun(dir, RunManifest.read(dir));
    }
  }
  throw ShutterException.noInput(
    'no run "$argument" (looked for a directory with manifest.json, '
    'and for an id under ${project.runsDir}).',
  );
}

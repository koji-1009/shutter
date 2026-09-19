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

/// `latest`, or `latest~N` for the run N before it.
final _latest = RegExp(r'^latest(?:~(\d{1,9}))?$');

/// Loads the run named by [argument]: `latest` / `latest~N`, a directory
/// containing `manifest.json`, or a run id under
/// `.dart_tool/shutter/runs/`.
StoredRun loadRun(Project project, String argument) {
  if (_latest.firstMatch(argument) case final match?) {
    final ids = _runIds(project);
    final back = int.parse(match.group(1) ?? '0');
    if (back >= ids.length) {
      throw ShutterException.noInput(
        'no run "$argument": ${ids.length} runs under ${project.runsDir}.',
      );
    }
    final dir = p.join(project.runsDir, ids[ids.length - 1 - back]);
    return StoredRun(dir, RunManifest.read(dir));
  }
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

/// Ids of the runs under `.dart_tool/shutter/runs/` whose manifest is
/// written, oldest first: by time, then by the `-N` suffix.
List<String> _runIds(Project project) {
  final runs = Directory(project.runsDir);
  if (!runs.existsSync()) return const [];
  return [
    for (final entity in runs.listSync())
      if (entity is Directory &&
          File(p.join(entity.path, manifestFileName)).existsSync())
        p.basename(entity.path),
  ]..sort((a, b) {
    final (baseA, suffixA) = _splitId(a);
    final (baseB, suffixB) = _splitId(b);
    final byBase = baseA.compareTo(baseB);
    return byBase != 0 ? byBase : suffixA.compareTo(suffixB);
  });
}

/// A run id as its time and its suffix (1 without one).
(String, int) _splitId(String id) {
  final dash = id.lastIndexOf('-');
  final suffix = dash < 0 ? null : int.tryParse(id.substring(dash + 1));
  return suffix == null ? (id, 1) : (id.substring(0, dash), suffix);
}

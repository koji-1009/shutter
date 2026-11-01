import 'package:collection/collection.dart';

import '../project/project.dart';
import '../run/run_store.dart';
import '../shutter_exception.dart';

/// The outcome of [prune]: absolute paths of the run directories, oldest
/// first.
final class const PruneResult({
  required final List<String> removed,
  required final List<String> kept,
}) {
  @override
  bool operator ==(Object other) =>
      other is PruneResult &&
      const ListEquality<String>().equals(other.removed, removed) &&
      const ListEquality<String>().equals(other.kept, kept);

  @override
  int get hashCode => Object.hash(
    const ListEquality<String>().hash(removed),
    const ListEquality<String>().hash(kept),
  );

  @override
  String toString() => 'PruneResult(removed: $removed, kept: $kept)';
}

/// Deletes every run under `.dart_tool/shutter/runs/` of the Flutter
/// project at or above [projectDir] but the newest [keep], as `shutter
/// prune --keep`, whoever shot them. A run still being shot is neither
/// counted nor deleted. Throws a [ShutterException] when [keep] is
/// negative or no project is found.
PruneResult prune(String projectDir, {required int keep}) {
  if (keep < 0) {
    throw ShutterException.usage('keep must not be negative ($keep).');
  }
  final (:removed, :kept) = pruneRuns(Project.find(projectDir), keep);
  return PruneResult(removed: removed, kept: kept);
}

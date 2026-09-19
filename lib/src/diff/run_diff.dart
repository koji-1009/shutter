import '../run/manifest.dart';

/// Classification of one id across two runs, in the order to look at.
enum DiffStatus { changed, added, removed, unchanged }

/// One id in a diff.
class const DiffEntry({
  required final DiffStatus status,

  /// The after shot, or the before shot for `removed`.
  required final Shot shot,

  /// Share of differing pixels on the union canvas; null when one side
  /// has no image.
  final double? diffRatio,

  /// The before shot's size, on a `changed` entry whose size changed.
  final (double, double)? beforeSize,

  /// The shot's PNG inside the before / after run directory.
  final String? beforePng,
  final String? afterPng,

  /// Image marking the differing pixels, inside the diff directory
  /// (`shutter diff --images`, `changed` entries only).
  final String? diffPng,
});

/// The outcome of comparing two runs.
class const RunDiff({
  /// Absolute run directories.
  required final String before,
  required final String after,

  /// Sorted by status, then by file and line.
  required final List<DiffEntry> entries,
}) {
  /// Count per status, every status present.
  Map<DiffStatus, int> get summary => {
    for (final status in DiffStatus.values)
      status: entries.where((e) => e.status == status).length,
  };

  /// 0 no differences, 1 differences.
  int get exitCode =>
      entries.every((e) => e.status == DiffStatus.unchanged) ? 0 : 1;
}

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import '../cli/context.dart';
import '../diff/composite.dart';
import '../diff/run_diff.dart';
import '../reporters/format.dart';
import '../run/manifest.dart';
import '../shutter_exception.dart';
import 'compare.dart';
import 'shot.dart';

/// The sheets [diff] writes, as `shutter diff --composite`: one image per
/// entry that has something to show, holding its before, diff, and after
/// panels, to attach on its own.
final class const DiffComposite({
  /// How the three panels are laid out.
  final CompositeDirection direction = CompositeDirection.auto,

  /// Text drawn above the panels of every sheet. Flutter renders it, so
  /// any script the host has a font for works, and it needs a Flutter
  /// SDK.
  final String? title,
}) {
  @override
  bool operator ==(Object other) =>
      other is DiffComposite &&
      other.direction == direction &&
      other.title == title;

  @override
  int get hashCode => Object.hash(direction, title);

  @override
  String toString() =>
      'DiffComposite(${['direction: ${direction.name}', if (title != null) 'title: $title'].join(', ')})';
}

/// A file a run read, as its manifest records it.
final class const ShotFile({
  /// Project-relative POSIX path, or absolute outside the project.
  required final String path,
  required final String sha256,
}) {
  @override
  bool operator ==(Object other) =>
      other is ShotFile && other.path == path && other.sha256 == sha256;

  @override
  int get hashCode => Object.hash(path, sha256);

  @override
  String toString() => 'ShotFile(path: $path, sha256: $sha256)';
}

/// What a run was shot with besides its subject: the arguments of [shot]
/// its manifest records. Two runs shot with different ones differ in
/// every image without any widget changing.
final class const ShotSetup({
  /// The shell file; none for shutter's default shell.
  final ShotFile? shell,

  /// Each action as given, e.g. `tap text:Save`.
  final List<String> actions = const [],
  final ShotCapture capture = const PreviewCapture(),
  final Keyboard? keyboard,

  /// The file served for each network image URL.
  final Map<String, ShotFile> networkImages = const {},

  /// Whether the images are of the semantics tree.
  final bool semantics = false,
  final ShotPlatform platform = ShotPlatform.android,

  /// The device pixel ratio the app was drawn at.
  final double pixelRatio = 2,
  final SafeAreaInsets? safeArea,
}) {
  @override
  bool operator ==(Object other) =>
      other is ShotSetup &&
      other.shell == shell &&
      const ListEquality<String>().equals(other.actions, actions) &&
      other.capture == capture &&
      other.keyboard == keyboard &&
      const MapEquality<String, ShotFile>().equals(
        other.networkImages,
        networkImages,
      ) &&
      other.semantics == semantics &&
      other.platform == platform &&
      other.pixelRatio == pixelRatio &&
      other.safeArea == safeArea;

  @override
  int get hashCode => Object.hash(
    shell,
    const ListEquality<String>().hash(actions),
    capture,
    keyboard,
    const MapEquality<String, ShotFile>().hash(networkImages),
    semantics,
    platform,
    pixelRatio,
    safeArea,
  );

  @override
  String toString() =>
      'ShotSetup(${[if (shell != null) 'shell: $shell', 'actions: $actions', 'capture: $capture', if (keyboard != null) 'keyboard: $keyboard', 'networkImages: $networkImages', 'semantics: $semantics', 'platform: ${platform.name}', 'pixelRatio: ${formatNumber(pixelRatio)}', if (safeArea != null) 'safeArea: $safeArea'].join(', ')})';
}

/// The outcome of [diff]: the two runs and each shot id across them.
final class const ShotDiff({
  /// Absolute paths of the run directories.
  required final String before,
  required final String after,

  /// What each run was shot with.
  required final ShotSetup beforeSetup,
  required final ShotSetup afterSetup,

  /// Absolute path of the directory the images went into; none when
  /// neither images nor a composite were asked for.
  final String? dir,

  /// Changed first, then added, removed, and unchanged; each in source
  /// order.
  required final List<ShotDiffEntry> entries,

  /// Why the title is missing from, or does not fit, some sheets.
  final List<String> warnings = const [],
}) {
  /// Whether any entry is not [DiffStatus.unchanged]; `shutter diff` exits
  /// 1 then.
  bool get hasChanges =>
      entries.any((entry) => entry.status != DiffStatus.unchanged);

  @override
  bool operator ==(Object other) =>
      other is ShotDiff &&
      other.before == before &&
      other.after == after &&
      other.beforeSetup == beforeSetup &&
      other.afterSetup == afterSetup &&
      other.dir == dir &&
      const ListEquality<ShotDiffEntry>().equals(other.entries, entries) &&
      const ListEquality<String>().equals(other.warnings, warnings);

  @override
  int get hashCode => Object.hash(
    before,
    after,
    beforeSetup,
    afterSetup,
    dir,
    const ListEquality<ShotDiffEntry>().hash(entries),
    const ListEquality<String>().hash(warnings),
  );

  @override
  String toString() =>
      'ShotDiff(${['before: $before', 'after: $after', 'beforeSetup: $beforeSetup', 'afterSetup: $afterSetup', if (dir != null) 'dir: $dir', 'entries: $entries', 'warnings: $warnings'].join(', ')})';
}

/// One shot id of a [ShotDiff].
final class const ShotDiffEntry({
  required final DiffStatus status,

  /// The after shot, or the before shot of a [DiffStatus.removed] one.
  required final ShotResult shot,

  /// Share of the pixels that differ, on the canvas both images cover;
  /// none when one side has no image.
  final double? diffRatio,

  /// The before shot's size, on a [DiffStatus.changed] entry whose size
  /// changed.
  final LogicalSize? beforeSize,

  /// Absolute paths of the before and after PNGs.
  final String? beforePng,
  final String? afterPng,

  /// Absolute path of the image marking the differing pixels in red, with
  /// images, on a [DiffStatus.changed] entry.
  final String? diffPng,

  /// Absolute path of the sheet, with a [DiffComposite].
  final String? compositePng,
}) {
  @override
  bool operator ==(Object other) =>
      other is ShotDiffEntry &&
      other.status == status &&
      other.shot == shot &&
      other.diffRatio == diffRatio &&
      other.beforeSize == beforeSize &&
      other.beforePng == beforePng &&
      other.afterPng == afterPng &&
      other.diffPng == diffPng &&
      other.compositePng == compositePng;

  @override
  int get hashCode => Object.hash(
    status,
    shot,
    diffRatio,
    beforeSize,
    beforePng,
    afterPng,
    diffPng,
    compositePng,
  );

  @override
  String toString() =>
      'ShotDiffEntry(${['status: ${status.name}', 'shot: $shot', if (diffRatio != null) 'diffRatio: $diffRatio', if (beforeSize != null) 'beforeSize: $beforeSize', if (beforePng != null) 'beforePng: $beforePng', if (afterPng != null) 'afterPng: $afterPng', if (diffPng != null) 'diffPng: $diffPng', if (compositePng != null) 'compositePng: $compositePng'].join(', ')})';
}

/// Compares two runs of the Flutter project at or above [projectDir]
/// pixel by pixel, by shot id, as `shutter diff` does. [before] and
/// [after] each name a run: a run directory (relative to [projectDir], or
/// absolute) such as [ShotRun.dir], a run id, `latest`, or `latest~N` for
/// the run N before it.
///
/// With [images], an image marking the differing pixels of each changed
/// entry is written; with [composite], a sheet for each entry that has
/// something to show. Both go into a new directory under
/// `.dart_tool/shutter/diffs/`.
///
/// Changes are the result, not an error. Throws a [ShutterException] when
/// a run is not found, or a [DiffComposite.title] is asked for and there
/// is no Flutter SDK to draw it.
Future<ShotDiff> diff(
  String projectDir,
  String before,
  String after, {
  bool images = false,
  DiffComposite? composite,
}) => compare(
  ShutterContext(workingDirectory: projectDir),
  before,
  after,
  images: images,
  composite: composite,
).then(shotDiff);

/// [compared] as [diff] returns it.
ShotDiff shotDiff(
  ({RunDiff diff, String? dir, List<String> warnings}) compared,
) {
  final (:diff, :dir, :warnings) = compared;
  String? under(String? base, String? name) =>
      base == null || name == null ? null : p.join(base, name);
  return ShotDiff(
    before: diff.before,
    after: diff.after,
    beforeSetup: _setup(diff.beforeShell, diff.beforeSetup),
    afterSetup: _setup(diff.afterShell, diff.afterSetup),
    dir: dir,
    entries: [
      for (final entry in diff.entries)
        ShotDiffEntry(
          status: entry.status,
          shot: shotResult(
            entry.shot,
            png: entry.status == DiffStatus.removed
                ? under(diff.before, entry.beforePng)
                : under(diff.after, entry.afterPng),
          ),
          diffRatio: entry.diffRatio,
          beforeSize: logicalSize(entry.beforeSize),
          beforePng: under(diff.before, entry.beforePng),
          afterPng: under(diff.after, entry.afterPng),
          diffPng: under(dir, entry.diffPng),
          compositePng: under(dir, entry.compositePng),
        ),
    ],
    warnings: warnings,
  );
}

ShotSetup _setup(ShellFile? shell, RunSetup setup) => ShotSetup(
  shell: _file(shell),
  actions: setup.actions,
  capture: setup.screen
      ? ScreenCapture(viewport: logicalSize(setup.viewport))
      : const PreviewCapture(),
  keyboard: switch (setup.keyboard) {
    final height? => Keyboard(height, tint: setup.keyboardTint),
    null => null,
  },
  networkImages: {
    for (final MapEntry(key: url, value: file) in setup.networkImages.entries)
      url: _file(file)!,
  },
  semantics: setup.semantics,
  platform: setup.platform,
  pixelRatio: setup.pixelRatio,
  safeArea: switch (setup.safeArea) {
    (final top, final bottom)? => SafeAreaInsets(top: top, bottom: bottom),
    null => null,
  },
);

ShotFile? _file(RecordedFile? file) => switch (file) {
  (:final path, :final sha256)? => ShotFile(path: path, sha256: sha256),
  null => null,
};

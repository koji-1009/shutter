/// Shutter as a Dart library: [shot] renders a Flutter project's previews,
/// or one widget expression, to PNG as a new run, [diff] compares two
/// runs, [doctor] checks what shooting needs, and [prune] deletes old
/// runs, as `shutter shot`, `shutter semantics`, `shutter diff`, `shutter
/// doctor`, and `shutter prune` do, without starting a process.
///
/// ```dart
/// import 'package:shutter/shutter.dart';
///
/// Future<void> main() async {
///   final run = await shot(
///     '/path/to/app',
///     const PreviewFiles(['lib/preview/notification_tile_preview.dart']),
///     onProgress: (event) => print(event.message),
///   );
///   for (final result in run.shots) {
///     print('${result.id} ${result.status.name} ${result.png}');
///   }
/// }
/// ```
///
/// A shot that fails to render is a [ShotStatus.error] in the run, and a
/// change between two runs is an entry of the diff; a run that cannot be
/// shot, or runs that cannot be compared, throw a [ShutterException].
library;

export 'src/api/diff.dart' hide shotDiff;
export 'src/api/doctor.dart' hide checkSetup, minimumFlutter;
export 'src/api/prune.dart';
export 'src/api/shot.dart' hide logicalSize, shotResult, shotRun;
export 'src/diff/composite.dart' show CompositeDirection;
export 'src/diff/run_diff.dart' show DiffStatus;
export 'src/engine/interaction.dart';
export 'src/engine/progress.dart';
export 'src/run/manifest.dart' show ShotPlatform, ShotStatus;
export 'src/shutter_exception.dart';

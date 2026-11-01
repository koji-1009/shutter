import 'package:path/path.dart' as p;

import '../cli/context.dart';
import '../cli/shot_options.dart';
import '../engine/engine.dart';
import '../engine/interaction.dart';
import '../project/project.dart';
import '../run/manifest.dart';
import '../run/timestamp_id.dart';
import '../scan/scanner.dart';
import '../shutter_exception.dart';
import 'progress.dart';

/// The `--widget` of a [ShotPlan]: its expression, the `--import` files
/// and URIs as given, its size, and whether it is laid out unbounded.
typedef WidgetPlan = ({
  String source,
  List<String> imports,
  (double, double)? size,
  bool unbounded,
});

/// A `shot` or `semantics` run as `shutter shot` and the library's `shot`
/// give it, each value already of its type. Paths are as given: relative
/// to the working directory, or absolute.
class const ShotPlan({
  /// The preview files; empty with [widget].
  final List<String> files = const [],
  final WidgetPlan? widget,
  final int settleMs = 300,

  /// The `--shell` file, or null for the preview dir's.
  final String? shell,
  final List<ShotAction> actions = const [],
  final bool screen = false,
  final (double, double)? viewport,
  final double? keyboard,
  final int? keyboardTint,

  /// The file served for each `--network-image` URL.
  final Map<String, String> networkImages = const {},
  final bool semantics = false,
  final ShotPlatform platform = ShotPlatform.android,
  final void Function(ShotProgress event)? onProgress,
});

/// Shoots [plan] into a new run under the project at or above the
/// working directory of [context]. Returns the run directory and its
/// manifest, written. Throws a [ShutterException], leaving the project
/// as it was, when the run cannot be shot.
Future<({String dir, RunManifest manifest})> shoot(
  ShutterContext context,
  ShotPlan plan,
) async {
  final networkImages = resolveNetworkImages(
    plan.networkImages,
    workingDirectory: context.workingDirectory,
  );
  final project = context.project();
  requireFlutterTest(project);
  final shell = resolveShell(
    project,
    plan.shell,
    workingDirectory: context.workingDirectory,
  );
  final sdk = context.sdk();
  final widget = switch (plan.widget) {
    final widget? => parseWidgetShot(
      project,
      source: widget.source,
      imports: widget.imports,
      size: widget.size,
      unbounded: widget.unbounded,
      workingDirectory: context.workingDirectory,
    ),
    null => null,
  };
  final paths = [
    for (final file in plan.files)
      libFile(
        project,
        file,
        workingDirectory: context.workingDirectory,
        what: 'preview file',
      ),
  ];
  if (paths.isNotEmpty) {
    plan.onProgress?.call(ScanStarted([...paths.map(project.relative)]));
  }
  final libraries = await Scanner(
    project,
    sdkPath: sdk.dartSdkPath,
  ).scan(paths);
  final found = {
    for (final library in libraries)
      for (final c in library.candidates) c.file,
  };
  for (final path in paths) {
    if (!found.contains(project.relative(path))) {
      throw ShutterException.noInput(
        '${project.relative(path)} has no @Preview.',
      );
    }
  }
  // Hashed before rendering, so the record is the file that was shot.
  final shellRecord = shell == null ? null : recordedFile(project, shell);
  final imageRecords = networkImageFiles(project, networkImages);
  final runDir = createTimestampDir(project.runsDir, context.clock());
  final engine = context.engineFactory(sdk);
  final shots = await engine.capture(
    CaptureRequest(
      project: project,
      libraries: libraries,
      runDir: runDir,
      settleMs: plan.settleMs,
      widget: widget,
      shell: shell,
      actions: plan.actions,
      screen: plan.screen,
      viewport: plan.viewport,
      keyboard: plan.keyboard,
      keyboardTint: plan.keyboardTint,
      networkImages: networkImages,
      semantics: plan.semantics,
      platform: plan.platform,
      onProgress: plan.onProgress,
    ),
  );
  final manifest = RunManifest(
    run: p.basename(runDir),
    shots: [...shots]..sort(Shot.bySource),
    shell: shellRecord,
    setup: (
      actions: [for (final action in plan.actions) action.label],
      screen: plan.screen,
      viewport: plan.viewport,
      keyboard: plan.keyboard,
      keyboardTint: plan.keyboardTint,
      networkImages: imageRecords,
      semantics: plan.semantics,
      platform: plan.platform,
    ),
  )..write(runDir);
  return (dir: runDir, manifest: manifest);
}

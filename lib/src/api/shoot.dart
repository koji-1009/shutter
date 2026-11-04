import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../cli/context.dart';
import '../engine/engine.dart';
import '../engine/interaction.dart';
import '../engine/progress.dart';
import '../engine/widget_shot.dart';
import '../project/project.dart';
import '../reporters/format.dart';
import '../run/manifest.dart';
import '../run/run_store.dart';
import '../run/timestamp_id.dart';
import '../scan/scanner.dart';
import '../shutter_exception.dart';
import 'shot.dart';

/// Shoots [subject] as [shot] does, in the project at or above the
/// working directory of [context], which relative paths are relative to.
/// Returns the new run, its manifest written. Throws a
/// [ShutterException], leaving the project as it was, when the run cannot
/// be shot. `shutter shot` reports the run; [shot] returns it as a
/// [ShotRun].
Future<StoredRun> shoot(
  ShutterContext context,
  ShotSubject subject, {
  Duration settle = const Duration(milliseconds: 300),
  String? shell,
  List<ShotAction> actions = const [],
  ShotCapture capture = const PreviewCapture(),
  Keyboard? keyboard,
  Map<String, String> networkImages = const {},
  ShotPlatform platform = ShotPlatform.android,
  double pixelRatio = defaultPixelRatio,
  bool semantics = false,
  void Function(ShotProgress event)? onProgress,
}) async {
  if (settle.isNegative) {
    throw ShutterException.usage('settle must not be negative ($settle).');
  }
  if (!(pixelRatio > 0 && pixelRatio.isFinite)) {
    throw ShutterException.usage(
      'pixel ratio must be > 0 and finite (got ${formatNumber(pixelRatio)}).',
    );
  }
  _checkActions(actions);
  final viewport = switch (capture) {
    ScreenCapture(:final viewport?) => _size(viewport, 'viewport'),
    _ => null,
  };
  if (keyboard != null) _checkKeyboard(keyboard, semantics: semantics);
  final widgetSize = switch (subject) {
    PreviewFiles(:final files) when files.isEmpty =>
      throw ShutterException.usage('PreviewFiles names no file.'),
    WidgetExpression(size: final LogicalSize size) => _size(
      size,
      'widget size',
    ),
    _ => null,
  };
  final workingDirectory = context.workingDirectory;
  final imagePaths = {
    for (final MapEntry(key: url, value: file) in networkImages.entries)
      url: _networkImageFile(url, file, workingDirectory),
  };
  final project = context.project();
  requireFlutterTest(project);
  final shellPath = _shell(project, shell, workingDirectory);
  final sdk = context.sdk();
  final (paths, widget) = switch (subject) {
    PreviewFiles(:final files) => (
      [
        for (final file in files)
          _libFile(project, file, workingDirectory, 'preview file'),
      ],
      null,
    ),
    WidgetExpression(:final expression, :final imports, :final size) => (
      const <String>[],
      WidgetShot(
        source: expression,
        imports: [
          'package:flutter/widgets.dart',
          for (final import in imports)
            import.startsWith('package:')
                ? import
                : project.packageUri(
                    _libFile(project, import, workingDirectory, 'import'),
                  ),
        ],
        size: widgetSize,
        unbounded: size is UnboundedSize,
      ),
    ),
  };
  if (paths.isNotEmpty) {
    onProgress?.call(ScanStarted([...paths.map(project.relative)]));
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
  final shellRecord = shellPath == null ? null : _record(project, shellPath);
  final imageRecords = {
    for (final MapEntry(key: url, value: path) in imagePaths.entries)
      url: _record(project, path),
  };
  final runDir = createTimestampDir(project.runsDir, context.clock());
  final engine = context.engineFactory(sdk);
  final shots = await engine.capture(
    CaptureRequest(
      project: project,
      libraries: libraries,
      runDir: runDir,
      settleMs: settle.inMilliseconds,
      widget: widget,
      shell: shellPath,
      actions: actions,
      screen: capture is ScreenCapture,
      viewport: viewport,
      keyboard: keyboard?.height,
      keyboardTint: keyboard?.tint,
      networkImages: imagePaths,
      semantics: semantics,
      platform: platform,
      pixelRatio: pixelRatio,
      onProgress: onProgress,
    ),
  );
  final manifest = RunManifest(
    run: p.basename(runDir),
    shots: [...shots]..sort(Shot.bySource),
    shell: shellRecord,
    setup: (
      actions: [for (final action in actions) action.label],
      screen: capture is ScreenCapture,
      viewport: viewport,
      keyboard: keyboard?.height,
      keyboardTint: keyboard?.tint,
      networkImages: imageRecords,
      semantics: semantics,
      platform: platform,
      pixelRatio: pixelRatio,
    ),
  )..write(runDir);
  return StoredRun(runDir, manifest);
}

/// Throws unless each action names its widget, and at most one is held,
/// last.
void _checkActions(List<ShotAction> actions) {
  for (final action in actions) {
    if (action.target.value.isEmpty) {
      throw ShutterException.usage(
        '${action.label}: the action names no widget.',
      );
    }
  }
  final held = actions.where((action) => action.kind.held).length;
  if (held > 1 || (held == 1 && !actions.last.kind.held)) {
    throw ShutterException.usage(
      'Give at most one press, hover, or focus action, last: its state '
      'lasts through the capture.',
    );
  }
}

/// [size] as the engine takes it, when both dimensions are > 0 and
/// finite. [what] names it in errors.
(double, double) _size(LogicalSize size, String what) {
  if (size.width > 0 &&
      size.height > 0 &&
      size.width.isFinite &&
      size.height.isFinite) {
    return (size.width, size.height);
  }
  throw ShutterException.usage(
    '$what must be > 0 and finite in both dimensions (got $size).',
  );
}

/// Throws unless [keyboard] is > 0 and finite high, with a tint that is
/// an ARGB color and not asked of the semantics tree.
void _checkKeyboard(Keyboard keyboard, {required bool semantics}) {
  if (!(keyboard.height > 0 && keyboard.height.isFinite)) {
    throw ShutterException.usage(
      'keyboard height must be a logical size > 0 (got ${keyboard.height}).',
    );
  }
  if (keyboard.tint case final tint? when tint < 0 || tint > 0xFFFFFFFF) {
    throw ShutterException.usage(
      'keyboard tint must be an ARGB color, 0x00000000 to 0xFFFFFFFF '
      '(got 0x${tint.toRadixString(16)}).',
    );
  }
  if (semantics && keyboard.tint != null) {
    throw ShutterException.usage(
      'semantics draws no keyboard tint: the keyboard is not in the '
      'semantics tree.',
    );
  }
}

/// Absolute path of the file served for the `http` or `https` [url],
/// [file] relative to [workingDirectory], which must exist.
String _networkImageFile(String url, String file, String workingDirectory) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !(uri.isScheme('http') || uri.isScheme('https')) ||
      uri.host.isEmpty) {
    throw ShutterException.usage(
      'network image URL $url must be http or https, with a host.',
    );
  }
  if (file.isEmpty) {
    throw ShutterException.usage('network image $url names no file.');
  }
  final path = p.normalize(p.join(workingDirectory, file));
  if (!File(path).existsSync()) {
    throw ShutterException.noInput('network image file $file does not exist.');
  }
  return path;
}

/// The shell file to use: [shell], relative to [workingDirectory], which
/// must exist, else `<preview dir>/shell.dart` when present, else null.
String? _shell(Project project, String? shell, String workingDirectory) {
  if (shell == null) return project.shellPath;
  final path = p.normalize(p.join(workingDirectory, shell));
  if (!File(path).existsSync()) {
    throw ShutterException.noInput('shell $shell does not exist.');
  }
  return path;
}

/// Absolute path of [path], relative to [workingDirectory], which must be
/// a file under `lib/`. [what] names it in errors.
String _libFile(
  Project project,
  String path,
  String workingDirectory,
  String what,
) {
  final resolved = p.normalize(p.join(workingDirectory, path));
  if (!File(resolved).existsSync()) {
    throw ShutterException.noInput('$what $path does not exist.');
  }
  if (!p.isWithin(project.libDir, resolved)) {
    throw ShutterException.usage('$what must be under lib/ ($path).');
  }
  return resolved;
}

/// The manifest record of the file at [path], such as the shell file.
RecordedFile _record(Project project, String path) => (
  path: project.shown(path),
  sha256: sha256.convert(File(path).readAsBytesSync()).toString(),
);

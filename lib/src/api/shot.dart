import 'package:collection/collection.dart';

import '../cli/context.dart';
import '../engine/interaction.dart';
import '../engine/progress.dart';
import '../reporters/format.dart';
import '../run/manifest.dart';
import '../run/run_store.dart';
import '../shutter_exception.dart';
import 'shoot.dart';

/// What a run shoots: the previews of [PreviewFiles], or one
/// [WidgetExpression].
sealed class ShotSubject {
  const ShotSubject();
}

/// The `@Preview` functions of these files, as `shutter shot <file>...`.
final class const PreviewFiles(
  /// Files under the project's `lib/`, relative to the project directory
  /// given to [shot], or absolute. Each must hold a preview.
  final List<String> files,
) extends ShotSubject {
  @override
  bool operator ==(Object other) =>
      other is PreviewFiles &&
      const ListEquality<String>().equals(other.files, files);

  @override
  int get hashCode => const ListEquality<String>().hash(files);

  @override
  String toString() => 'PreviewFiles(files: $files)';
}

/// One widget expression, without a preview file, as `shutter shot
/// --widget`.
final class const WidgetExpression(
  /// Dart expression of type `Widget`, e.g. `PrimaryButton(label: "OK")`.
  final String expression, {

  /// Files under `lib/` (relative to the project directory, or absolute)
  /// and `package:` URIs the expression needs imported;
  /// `package:flutter/widgets.dart` is always imported.
  final List<String> imports = const [],

  /// The size to lay it out at; none stops its width at the viewport's.
  final WidgetSize? size,
}) extends ShotSubject {
  @override
  bool operator ==(Object other) =>
      other is WidgetExpression &&
      other.expression == expression &&
      const ListEquality<String>().equals(other.imports, imports) &&
      other.size == size;

  @override
  int get hashCode =>
      Object.hash(expression, const ListEquality<String>().hash(imports), size);

  @override
  String toString() =>
      'WidgetExpression(${['expression: $expression', 'imports: $imports', if (size != null) 'size: $size'].join(', ')})';
}

/// The size of a [WidgetExpression]: a [LogicalSize], or
/// [WidgetSize.unbounded].
sealed class WidgetSize {
  const WidgetSize();

  /// Neither dimension bounded: the widget is shot at its own size, as
  /// `--size unbounded`.
  static const WidgetSize unbounded = UnboundedSize._();
}

/// A size in logical pixels.
final class const LogicalSize(final double width, final double height)
    extends WidgetSize {
  @override
  bool operator ==(Object other) =>
      other is LogicalSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  /// `390x844`, as on the command line.
  @override
  String toString() => '${formatNumber(width)}x${formatNumber(height)}';
}

/// [WidgetSize.unbounded].
final class UnboundedSize extends WidgetSize {
  const UnboundedSize._();

  @override
  String toString() => 'unbounded';
}

/// What a shot's PNG holds, as `--capture`.
sealed class ShotCapture {
  const ShotCapture();
}

/// The preview alone.
final class PreviewCapture extends ShotCapture {
  const PreviewCapture();

  @override
  bool operator ==(Object other) => other is PreviewCapture;

  @override
  int get hashCode => (PreviewCapture).hashCode;

  @override
  String toString() => 'PreviewCapture()';
}

/// The whole screen: the viewport, with the menus and dialogs the app
/// draws above the preview.
final class const ScreenCapture({
  /// The viewport, the preview at its top left; none keeps the one the
  /// preview's size gives.
  final LogicalSize? viewport,
}) extends ShotCapture {
  @override
  bool operator ==(Object other) =>
      other is ScreenCapture && other.viewport == viewport;

  @override
  int get hashCode => Object.hash(ScreenCapture, viewport);

  @override
  String toString() =>
      'ScreenCapture(${viewport == null ? '' : 'viewport: $viewport'})';
}

/// An on-screen keyboard to lay the preview out with, as `--keyboard`
/// (experimental). The keyboard itself is not drawn.
final class const Keyboard(
  /// Its height in logical pixels.
  final double height, {

  /// ARGB color to paint its area in, e.g. `0xFF9E9E9E`, as
  /// `--keyboard-tint`; none leaves the area as the app paints it. Not
  /// with `semantics`.
  final int? tint,
}) {
  @override
  bool operator ==(Object other) =>
      other is Keyboard && other.height == height && other.tint == tint;

  @override
  int get hashCode => Object.hash(height, tint);

  @override
  String toString() =>
      'Keyboard(${['height: ${formatNumber(height)}', if (tint case final tint?) 'tint: ${colorLiteral(tint)}'].join(', ')})';
}

/// The safe area of the device the app is laid out for, as `--safe-area`:
/// the insets of its status bar or notch and of its home indicator, in
/// logical pixels. They are reported to the app as the view padding and
/// not drawn.
final class const SafeAreaInsets({
  /// The inset at the top, such as the status bar's.
  final double top = 0,

  /// The inset at the bottom, such as the home indicator's.
  final double bottom = 0,
}) {
  @override
  bool operator ==(Object other) =>
      other is SafeAreaInsets && other.top == top && other.bottom == bottom;

  @override
  int get hashCode => Object.hash(top, bottom);

  @override
  String toString() =>
      'SafeAreaInsets(top: ${formatNumber(top)}, bottom: ${formatNumber(bottom)})';
}

/// The outcome of [shot]: the run directory and each shot in it.
final class const ShotRun({
  /// Run id, e.g. `20260919T143503Z`; `shutter diff` names the run by it.
  required final String id,

  /// Absolute path of the run directory, holding `manifest.json` and the
  /// PNGs.
  required final String dir,

  /// The shots, in source order: file, line, then id.
  required final List<ShotResult> shots,
}) {
  /// Whether any shot is an [ShotStatus.error]; `shutter shot` exits 2
  /// then.
  bool get hasErrors => shots.any((s) => s.status == ShotStatus.error);

  @override
  bool operator ==(Object other) =>
      other is ShotRun &&
      other.id == id &&
      other.dir == dir &&
      const ListEquality<ShotResult>().equals(other.shots, shots);

  @override
  int get hashCode =>
      Object.hash(id, dir, const ListEquality<ShotResult>().hash(shots));

  @override
  String toString() => 'ShotRun(id: $id, dir: $dir, shots: $shots)';
}

/// One shot of a [ShotRun].
final class const ShotResult({
  /// `<static>.<runtime>`: the same preview has the same id in every run.
  required final String id,
  required final ShotStatus status,

  /// `Preview.name`, else the declaration (`fn`, `Class.method`), else
  /// the widget expression.
  required final String name,

  /// Project-relative path and 1-based line of the preview's annotation;
  /// none for a widget expression.
  final String? file,
  final int? line,

  /// Logical size of the captured image.
  final LogicalSize? size,

  /// `light` / `dark` when the preview sets `brightness`.
  final String? brightness,
  final double? textScaleFactor,

  /// Absolute path of the PNG. An `error` shot has one when rendering got
  /// far enough to paint.
  final String? png,

  /// First line of the first error of an `error` shot.
  final String? error,

  /// `path:line:column` inside the project where the error points.
  final String? at,
}) {
  @override
  bool operator ==(Object other) =>
      other is ShotResult &&
      other.id == id &&
      other.status == status &&
      other.name == name &&
      other.file == file &&
      other.line == line &&
      other.size == size &&
      other.brightness == brightness &&
      other.textScaleFactor == textScaleFactor &&
      other.png == png &&
      other.error == error &&
      other.at == at;

  @override
  int get hashCode => Object.hash(
    id,
    status,
    name,
    file,
    line,
    size,
    brightness,
    textScaleFactor,
    png,
    error,
    at,
  );

  @override
  String toString() =>
      'ShotResult(${['id: $id', 'status: ${status.name}', 'name: $name', if (file != null) 'file: $file', if (line != null) 'line: $line', if (size != null) 'size: $size', if (brightness != null) 'brightness: $brightness', if (textScaleFactor != null) 'textScaleFactor: $textScaleFactor', if (png != null) 'png: $png', if (error != null) 'error: $error', if (at != null) 'at: $at'].join(', ')})';
}

/// Shoots [subject] in the Flutter project at or above [projectDir] into
/// a new run, as `shutter shot`, or `shutter semantics` with
/// [semantics]. Relative paths, of preview files, imports, [shell], and
/// [networkImages] files, are relative to [projectDir]; the current
/// directory plays no part.
///
/// A shot that fails to render is a [ShotStatus.error] in the returned
/// run. A run that cannot be shot throws a [ShutterException] instead,
/// leaving the project as it was: no Flutter SDK, arguments that do not
/// fit together, a missing file, or a project that cannot render.
///
/// - [settle]: pumped once before capture, and again, in 16 ms frames,
///   after each action.
/// - [shell]: the shell file to use instead of `<preview dir>/shell.dart`.
/// - [actions]: performed on every preview before the capture, in order;
///   at most one press, hover, or focus, which comes last.
/// - [networkImages]: the file served to `Image.network` for each URL.
/// - [platform]: the platform the app is drawn as.
/// - [pixelRatio]: the device pixel ratio the app is drawn at, > 0: pixels
///   of the PNG per logical pixel.
/// - [safeArea]: the safe area the app is laid out with; none lays it out
///   without one.
/// - [brightness], [textScale]: the platform brightness and text scale
///   (> 0) reported to every preview that sets none of its own.
/// - [onProgress]: told of what the run is doing as it does it.
Future<ShotRun> shot(
  String projectDir,
  ShotSubject subject, {
  Duration settle = const Duration(milliseconds: 300),
  String? shell,
  List<ShotAction> actions = const [],
  ShotCapture capture = const PreviewCapture(),
  Keyboard? keyboard,
  Map<String, String> networkImages = const {},
  ShotPlatform platform = ShotPlatform.android,
  double pixelRatio = 2,
  SafeAreaInsets? safeArea,
  ShotBrightness brightness = ShotBrightness.light,
  double textScale = 1,
  bool semantics = false,
  void Function(ShotProgress event)? onProgress,
}) => shoot(
  ShutterContext(workingDirectory: projectDir),
  subject,
  settle: settle,
  shell: shell,
  actions: actions,
  capture: capture,
  keyboard: keyboard,
  networkImages: networkImages,
  platform: platform,
  pixelRatio: pixelRatio,
  safeArea: safeArea,
  brightness: brightness,
  textScale: textScale,
  semantics: semantics,
  onProgress: onProgress,
).then(shotRun);

/// [run] as [shot] returns it.
ShotRun shotRun(StoredRun run) => ShotRun(
  id: run.manifest.run,
  dir: run.dir,
  shots: [
    for (final shot in run.manifest.shots)
      shotResult(shot, png: run.pngPath(shot)),
  ],
);

/// [shot] as a [ShotResult], its PNG at the absolute path [png].
ShotResult shotResult(Shot shot, {required String? png}) => ShotResult(
  id: shot.id,
  status: shot.status,
  name: shot.name,
  file: shot.file,
  line: shot.line,
  size: logicalSize(shot.size),
  brightness: shot.brightness,
  textScaleFactor: shot.textScaleFactor,
  png: png,
  error: shot.error,
  at: shot.at,
);

/// [size], `(width, height)`, as a [LogicalSize].
LogicalSize? logicalSize((double, double)? size) => switch (size) {
  (final width, final height)? => LogicalSize(width, height),
  null => null,
};

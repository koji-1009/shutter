import 'package:path/path.dart' as p;

import '../cli/context.dart';
import '../engine/interaction.dart';
import '../run/manifest.dart';
import '../shutter_exception.dart';
import 'progress.dart';
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
) extends ShotSubject;

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
}) extends ShotSubject;

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
  String toString() => '${_number(width)}x${_number(height)}';
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
}

/// The whole screen: the viewport, with the menus and dialogs the app
/// draws above the preview.
final class const ScreenCapture({
  /// The viewport, the preview at its top left; none keeps the one the
  /// preview's size gives.
  final LogicalSize? viewport,
}) extends ShotCapture;

/// An on-screen keyboard to lay the preview out with, as `--keyboard`
/// (experimental). The keyboard itself is not drawn.
final class const Keyboard(
  /// Its height in logical pixels.
  final double height, {

  /// ARGB color to paint its area in, e.g. `0xFF9E9E9E`, as
  /// `--keyboard-tint`; none leaves the area as the app paints it. Not
  /// with `semantics`.
  final int? tint,
});

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
});

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
  bool semantics = false,
  void Function(ShotProgress event)? onProgress,
}) => shotIn(
  ShutterContext(workingDirectory: projectDir),
  subject,
  settle: settle,
  shell: shell,
  actions: actions,
  capture: capture,
  keyboard: keyboard,
  networkImages: networkImages,
  platform: platform,
  semantics: semantics,
  onProgress: onProgress,
);

/// [shot] against [context].
Future<ShotRun> shotIn(
  ShutterContext context,
  ShotSubject subject, {
  required Duration settle,
  required String? shell,
  required List<ShotAction> actions,
  required ShotCapture capture,
  required Keyboard? keyboard,
  required Map<String, String> networkImages,
  required ShotPlatform platform,
  required bool semantics,
  required void Function(ShotProgress event)? onProgress,
}) async {
  if (settle.isNegative) {
    throw ShutterException.usage('settle must not be negative ($settle).');
  }
  _checkActions(actions);
  final viewport = switch (capture) {
    ScreenCapture(:final viewport?) => _size(viewport, 'viewport'),
    _ => null,
  };
  if (keyboard != null) {
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
  final (files, widget) = switch (subject) {
    PreviewFiles(:final files) when files.isEmpty =>
      throw ShutterException.usage('PreviewFiles names no file.'),
    PreviewFiles(:final files) => (files, null),
    WidgetExpression(:final expression, :final imports, :final size) => (
      const <String>[],
      (
        source: expression,
        imports: imports,
        size: switch (size) {
          final LogicalSize size => _size(size, 'widget size'),
          _ => null,
        },
        unbounded: size is UnboundedSize,
      ),
    ),
  };
  final (:dir, :manifest) = await shoot(
    context,
    ShotPlan(
      files: files,
      widget: widget,
      settleMs: settle.inMilliseconds,
      shell: shell,
      actions: actions,
      screen: capture is ScreenCapture,
      viewport: viewport,
      keyboard: keyboard?.height,
      keyboardTint: keyboard?.tint,
      networkImages: networkImages,
      semantics: semantics,
      platform: platform,
      onProgress: onProgress,
    ),
  );
  return ShotRun(
    id: manifest.run,
    dir: dir,
    shots: [
      for (final shot in manifest.shots)
        ShotResult(
          id: shot.id,
          status: shot.status,
          name: shot.name,
          file: shot.file,
          line: shot.line,
          size: switch (shot.size) {
            (final width, final height)? => LogicalSize(width, height),
            null => null,
          },
          brightness: shot.brightness,
          textScaleFactor: shot.textScaleFactor,
          png: switch (shot.png) {
            final png? => p.join(dir, png),
            null => null,
          },
          error: shot.error,
          at: shot.at,
        ),
    ],
  );
}

/// Throws unless each action names its widget, and at most one is held,
/// last.
void _checkActions(List<ShotAction> actions) {
  for (final action in actions) {
    if (action.value.isEmpty) {
      throw ShutterException.usage(
        '${action.label}: the action names no widget.',
      );
    }
  }
  final held = actions.where((action) => action.held).length;
  if (held > 1 || (held == 1 && !actions.last.held)) {
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

String _number(double value) =>
    value.isFinite ? '${jsonNumber(value)}' : '$value';

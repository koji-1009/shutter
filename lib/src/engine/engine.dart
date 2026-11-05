import '../project/project.dart';
import '../run/manifest.dart';
import '../scan/candidate.dart';
import 'interaction.dart';
import 'progress.dart';
import 'widget_shot.dart';

/// What an engine is asked to capture.
class const CaptureRequest({
  required final Project project,

  /// Scanned candidates of the named preview files.
  required final List<SourceLibrary> libraries,

  /// Absolute run directory; PNGs land here as `<id>.png`.
  required final String runDir,
  required final int settleMs,

  /// The `--widget` expression, shot without a preview file.
  final WidgetShot? widget,

  /// Absolute path of the shell file, or null for the default shell.
  final String? shell,

  /// Performed on every preview before the capture, in order.
  final List<ShotAction> actions = const [],

  /// Capture the whole viewport, overlays included, rather than the
  /// preview.
  final bool screen = false,

  /// Logical viewport replacing the one the preview's size gives.
  final (double, double)? viewport,

  /// Logical height of an on-screen keyboard, reported to the app as the
  /// bottom view inset.
  final double? keyboard,

  /// ARGB color the keyboard's area is painted in; none leaves it as the
  /// app paints it.
  final int? keyboardTint,

  /// Absolute path of the file served for each `--network-image` URL.
  final Map<String, String> networkImages = const {},

  /// Draw the semantics tree of what is captured instead of what the app
  /// paints.
  final bool semantics = false,

  /// The platform the app is drawn as.
  final ShotPlatform platform = ShotPlatform.android,

  /// The device pixel ratio the app is drawn at: pixels of the PNG per
  /// logical pixel.
  final double pixelRatio = defaultPixelRatio,

  /// Logical safe area insets, top and bottom, reported to the app as the
  /// view padding.
  final (double, double)? safeArea,

  /// The platform brightness and text scale reported to every preview
  /// that sets none.
  final ShotBrightness brightness = ShotBrightness.light,
  final double textScale = 1,

  /// The locale reported as the device's: language, script, and country
  /// codes.
  final (String, String?, String?)? locale,

  /// Told of each render as it starts, each shot as it finishes, and each
  /// font download.
  final void Function(ShotProgress event)? onProgress,
});

/// The only swappable layer: turns scanned previews and a `--widget` into
/// PNGs and shot records. The run and diff layers do not know which
/// engine produced a run.
abstract interface class Engine {
  /// Renders every candidate and the widget in [request] and returns
  /// one [Shot] per resolved preview (plus one error shot per candidate,
  /// or for the widget, that could not be compiled).
  Future<List<Shot>> capture(CaptureRequest request);
}

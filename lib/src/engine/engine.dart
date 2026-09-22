import '../project/project.dart';
import '../run/manifest.dart';
import '../scan/candidate.dart';
import 'interaction.dart';
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

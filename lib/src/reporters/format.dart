import '../run/manifest.dart';
import 'yaml_scalar.dart';

/// `200` for integral values, `0.5` otherwise.
String formatNumber(double value) => jsonNumber(value).toString();

/// `[200, 56]`.
String formatSize((double, double) size) =>
    '[${formatNumber(size.$1)}, ${formatNumber(size.$2)}]';

/// `{path: ..., sha256: ...}`, or `default` for the default shell.
String formatShell(ShellFile? shell) => switch (shell) {
  (:final path, :final sha256) =>
    '{path: ${yamlScalar(path)}, sha256: $sha256}',
  null => 'default',
};

/// `["tap text:Save", "press key:ok"]`.
String formatActions(List<String> actions) =>
    '[${actions.map(yamlScalar).join(', ')}]';

/// The `actions` line of a run's [setup], only when it has actions.
void writeSetup(StringBuffer body, RunSetup setup) {
  if (setup.actions.isNotEmpty) {
    body.writeln('actions: ${formatActions(setup.actions)}');
  }
}

/// `<key>: []` or `<key>:`, the list header of a report.
String listHeader(String key, int length) => length == 0 ? '$key: []' : '$key:';

/// The fields every report entry starts with: [shot]'s id, [status], and
/// what describes the shot.
void writeEntryHead(StringBuffer body, String status, Shot shot) {
  body
    ..writeln('  - id: ${yamlScalar(shot.id)}')
    ..writeln('    status: $status')
    ..writeln('    name: ${yamlScalar(shot.name)}');
  if (shot.location case final location?) {
    body.writeln('    file: ${yamlScalar(location)}');
  }
  if (shot.size case final size?) {
    body.writeln('    size: ${formatSize(size)}');
  }
  if (shot.brightness case final brightness?) {
    body.writeln('    brightness: $brightness');
  }
  if (shot.textScaleFactor case final scale?) {
    body.writeln('    text_scale_factor: ${formatNumber(scale)}');
  }
}

/// `error` / `at` of [shot].
void writeError(StringBuffer body, Shot shot) {
  if (shot.error case final error?) {
    body.writeln('    error: ${yamlScalar(error)}');
  }
  if (shot.at case final at?) body.writeln('    at: ${yamlScalar(at)}');
}

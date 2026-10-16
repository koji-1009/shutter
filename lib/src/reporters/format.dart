import '../run/manifest.dart';
import 'yaml_scalar.dart';

/// `200` for integral values, `0.5` otherwise.
String formatNumber(double value) => jsonNumber(value).toString();

/// `[200, 56]`.
String formatSize((double, double) size) =>
    '[${formatNumber(size.$1)}, ${formatNumber(size.$2)}]';

/// `{path: ..., sha256: ...}`.
String formatFile(RecordedFile file) =>
    '{path: ${yamlScalar(file.path)}, sha256: ${file.sha256}}';

/// `{path: ..., sha256: ...}`, or `default` for the default shell.
String formatShell(ShellFile? shell) => switch (shell) {
  final shell? => formatFile(shell),
  null => 'default',
};

/// `"#FF9E9E9E"`, or `none` for a run shot without `--keyboard-tint`.
String formatKeyboardTint(int? tint) => switch (tint) {
  final argb? => yamlScalar(colorHex(argb)),
  null => 'none',
};

/// `{<url>: {path: ..., sha256: ...}}`, or `none` for a run shot without
/// `--network-image`.
String formatNetworkImages(Map<String, RecordedFile> images) {
  if (images.isEmpty) return 'none';
  final entries = [
    for (final MapEntry(:key, :value) in images.entries)
      '${yamlScalar(key)}: ${formatFile(value)}',
  ];
  return '{${entries.join(', ')}}';
}

/// `["tap text:Save", "press key:ok"]`.
String formatActions(List<String> actions) =>
    '[${actions.map(yamlScalar).join(', ')}]';

/// `screen` or `preview`.
String formatCapture(bool screen) => screen ? 'screen' : 'preview';

/// `[390, 844]`, or `default` for the viewport the preview's size gives.
String formatViewport((double, double)? viewport) => switch (viewport) {
  final size? => formatSize(size),
  null => 'default',
};

/// `336`, or `none` for a run shot without `--keyboard`.
String formatKeyboard(double? keyboard) => switch (keyboard) {
  final height? => formatNumber(height),
  null => 'none',
};

/// The `actions`, `capture`, `viewport`, `keyboard`, `keyboard_tint`, and
/// `network_images` lines of a run's [setup], each only when set.
void writeSetup(StringBuffer body, RunSetup setup) {
  if (setup.actions.isNotEmpty) {
    body.writeln('actions: ${formatActions(setup.actions)}');
  }
  if (setup.screen) body.writeln('capture: ${formatCapture(true)}');
  if (setup.viewport case final viewport?) {
    body.writeln('viewport: ${formatViewport(viewport)}');
  }
  if (setup.keyboard case final keyboard?) {
    body.writeln('keyboard: ${formatKeyboard(keyboard)}');
  }
  if (setup.keyboardTint case final tint?) {
    body.writeln('keyboard_tint: ${formatKeyboardTint(tint)}');
  }
  if (setup.networkImages.isNotEmpty) {
    body.writeln('network_images: ${formatNetworkImages(setup.networkImages)}');
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

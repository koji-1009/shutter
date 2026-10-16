import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// File name of a run's manifest.
const manifestFileName = 'manifest.json';

/// Integral doubles as ints (`200` rather than `200.0`).
num jsonNumber(double value) =>
    value == value.roundToDouble() ? value.toInt() : value;

/// Outcome of one shot.
enum ShotStatus { ok, error }

/// One captured (or failed) preview inside a run.
class const Shot({
  /// `<static>.<runtime>`; see `doc/manual.md` ("Ids").
  required final String id,
  required final ShotStatus status,

  /// `Preview.name`, else the declaration (`fn`, `Class.method`), else
  /// the `--widget` expression.
  required final String name,

  /// Project-relative path and 1-based line of the annotation.
  final String? file,
  final int? line,

  /// Logical size of the captured image.
  final (double, double)? size,

  /// `light` / `dark` when the preview sets `brightness`.
  final String? brightness,
  final double? textScaleFactor,

  /// File name of the PNG inside the run directory. Present on `error`
  /// shots too when rendering got far enough to paint.
  final String? png,

  /// First line of the first error.
  final String? error,

  /// `path:line:column` inside the project where the error points.
  final String? at,
}) {
  factory Shot.fromJson(Map<String, Object?> json) => Shot(
    id: json['id'] as String,
    status: ShotStatus.values.byName(json['status'] as String),
    file: json['file'] as String?,
    line: json['line'] as int?,
    name: json['name'] as String,
    size: switch (json['size']) {
      [final num w, final num h] => (w.toDouble(), h.toDouble()),
      _ => null,
    },
    brightness: json['brightness'] as String?,
    textScaleFactor: (json['text_scale_factor'] as num?)?.toDouble(),
    png: json['png'] as String?,
    error: json['error'] as String?,
    at: json['at'] as String?,
  );

  /// `file:line`, or just the file.
  String? get location =>
      file == null ? null : (line == null ? file : '$file:$line');

  /// This shot as an `error` shot pointing at its preview, keeping
  /// everything else.
  Shot withError(String error) => Shot(
    id: id,
    status: ShotStatus.error,
    file: file,
    line: line,
    name: name,
    size: size,
    brightness: brightness,
    textScaleFactor: textScaleFactor,
    png: png,
    error: error,
    at: location,
  );

  /// Source order: file, line, then id.
  static int bySource(Shot a, Shot b) {
    final byFile = (a.file ?? '').compareTo(b.file ?? '');
    if (byFile != 0) return byFile;
    final byLine = (a.line ?? 0).compareTo(b.line ?? 0);
    return byLine != 0 ? byLine : a.id.compareTo(b.id);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'status': status.name,
    'file': ?file,
    'line': ?line,
    'name': name,
    if (size case (final w, final h)?) 'size': [jsonNumber(w), jsonNumber(h)],
    'brightness': ?brightness,
    'text_scale_factor': ?textScaleFactor,
    'png': ?png,
    'error': ?error,
    'at': ?at,
  };
}

/// A file a run read: its path (project-relative, or absolute outside the
/// project) and the sha256 of its bytes.
typedef RecordedFile = ({String path, String sha256});

/// The shell file a run was shot with.
typedef ShellFile = RecordedFile;

/// What a run did to every preview besides rendering it: the actions
/// performed before the capture, whether the whole viewport was
/// captured, the `--viewport`, the `--keyboard` height and its
/// `--keyboard-tint` (ARGB), and the file served for each
/// `--network-image` URL.
typedef RunSetup = ({
  List<String> actions,
  bool screen,
  (double, double)? viewport,
  double? keyboard,
  int? keyboardTint,
  Map<String, RecordedFile> networkImages,
});

/// [argb] as `#AARRGGBB`.
String colorHex(int argb) =>
    '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';

/// The setup of a run shot without actions, of the preview alone.
const RunSetup plainSetup = (
  actions: [],
  screen: false,
  viewport: null,
  keyboard: null,
  keyboardTint: null,
  networkImages: {},
);

RecordedFile? _recordedFile(Object? json) => switch (json) {
  {'path': final String path, 'sha256': final String sha256} => (
    path: path,
    sha256: sha256,
  ),
  _ => null,
};

Map<String, Object?> _recordedFileJson(RecordedFile file) => {
  'path': file.path,
  'sha256': file.sha256,
};

/// `manifest.json` of one run directory.
class const RunManifest({
  /// Run id (`YYYYMMDDTHHMMSSZ`, suffixed on collision).
  required final String run,
  required final List<Shot> shots,

  /// The shell file, or null for the default shell.
  final ShellFile? shell,

  /// What the run did besides rendering; see [RunSetup].
  final RunSetup setup = plainSetup,
}) {
  factory RunManifest.fromJson(Map<String, Object?> json) => RunManifest(
    run: json['run'] as String,
    shots: [
      for (final shot in json['shots'] as List<Object?>)
        Shot.fromJson(shot as Map<String, Object?>),
    ],
    shell: _recordedFile(json['shell']),
    setup: (
      actions: [...?(json['actions'] as List<Object?>?)?.cast<String>()],
      screen: json['capture'] == 'screen',
      viewport: switch (json['viewport']) {
        [final num w, final num h] => (w.toDouble(), h.toDouble()),
        _ => null,
      },
      keyboard: (json['keyboard'] as num?)?.toDouble(),
      keyboardTint: switch (json['keyboard_tint']) {
        final String hex => int.parse(hex.substring(1), radix: 16),
        _ => null,
      },
      networkImages: {
        for (final MapEntry(:key, :value)
            in ((json['network_images'] as Map<String, Object?>?) ?? {})
                .entries)
          key: ?_recordedFile(value),
      },
    ),
  );

  /// Reads `<dir>/manifest.json`.
  factory RunManifest.read(String dir) => RunManifest.fromJson(
    jsonDecode(File(p.join(dir, manifestFileName)).readAsStringSync())
        as Map<String, Object?>,
  );

  /// 0 when every shot is ok, 2 when any is an `error`.
  int get exitCode => shots.any((s) => s.status == ShotStatus.error) ? 2 : 0;

  Map<String, Object?> toJson() {
    final (
      :actions,
      :screen,
      :viewport,
      :keyboard,
      :keyboardTint,
      :networkImages,
    ) = setup;
    return {
      'run': run,
      if (shell case final shell?) 'shell': _recordedFileJson(shell),
      if (actions.isNotEmpty) 'actions': actions,
      if (screen) 'capture': 'screen',
      if (viewport case (final w, final h)?)
        'viewport': [jsonNumber(w), jsonNumber(h)],
      if (keyboard != null) 'keyboard': jsonNumber(keyboard),
      if (keyboardTint != null) 'keyboard_tint': colorHex(keyboardTint),
      if (networkImages.isNotEmpty)
        'network_images': {
          for (final MapEntry(:key, :value) in networkImages.entries)
            key: _recordedFileJson(value),
        },
      'shots': [for (final shot in shots) shot.toJson()],
    };
  }

  /// Writes `<dir>/manifest.json` as indented JSON.
  void write(String dir) => File(
    p.join(dir, manifestFileName),
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(this)}\n');
}

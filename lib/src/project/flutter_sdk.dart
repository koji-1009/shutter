import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../shutter_exception.dart';

/// How to make a Flutter SDK findable.
const flutterSdkHint = 'set FLUTTER_ROOT or put `flutter` on PATH';

String _executableName(bool windows) => windows ? 'flutter.bat' : 'flutter';

/// A Flutter SDK checkout.
class FlutterSdk(final String root) {
  /// Finds the SDK through `FLUTTER_ROOT`, then through a `flutter`
  /// executable on `PATH`. A `flutter` that is not inside an SDK (a
  /// version manager's shim) is asked for its root with
  /// `flutter --version --machine`. Returns null when nothing is found.
  static FlutterSdk? locate({
    required Map<String, String> environment,
    bool? isWindows,
    ProcessResult Function(String executable, List<String> arguments)? runSync,
  }) {
    final windows = isWindows ?? Platform.isWindows;
    final flutterRoot = environment['FLUTTER_ROOT'];
    if (flutterRoot != null && flutterRoot.isNotEmpty) {
      return FlutterSdk(flutterRoot);
    }
    final executable = _executableName(windows);
    final separator = windows ? ';' : ':';
    for (final dir in (environment['PATH'] ?? '').split(separator)) {
      if (dir.isEmpty) continue;
      final candidate = File(p.join(dir, executable));
      if (!candidate.existsSync()) continue;
      final resolved = candidate.resolveSymbolicLinksSync();
      final root = p.dirname(p.dirname(resolved));
      if (Directory(p.join(root, 'packages', 'flutter')).existsSync()) {
        return FlutterSdk(root);
      }
      if (_askRoot(candidate.path, runSync ?? Process.runSync) case final r?) {
        return FlutterSdk(r);
      }
    }
    return null;
  }

  /// `flutterRoot` from `<executable> --version --machine`, or null.
  static String? _askRoot(
    String executable,
    ProcessResult Function(String, List<String>) runSync,
  ) {
    try {
      final result = runSync(executable, const ['--version', '--machine']);
      if (result.exitCode != 0) return null;
      final json = jsonDecode('${result.stdout}');
      return json is Map<String, Object?> && json['flutterRoot'] is String
          ? json['flutterRoot']! as String
          : null;
    } on Object {
      return null;
    }
  }

  /// [locate] or a [ShutterException] naming what is missing.
  static FlutterSdk require({required Map<String, String> environment}) {
    final sdk = locate(environment: environment);
    if (sdk == null) {
      throw ShutterException.unavailable(
        'Flutter SDK not found: $flutterSdkHint.',
      );
    }
    return sdk;
  }

  /// `bin/flutter` (`bin/flutter.bat` on Windows).
  String executable({bool? isWindows}) =>
      p.join(root, 'bin', _executableName(isWindows ?? Platform.isWindows));

  /// The Dart SDK shipped with Flutter, which projects are analyzed with.
  String get dartSdkPath => p.join(root, 'bin', 'cache', 'dart-sdk');

  /// Where the SDK caches Roboto and MaterialIcons.
  String get materialFontsDir =>
      p.join(root, 'bin', 'cache', 'artifacts', 'material_fonts');

  /// Framework version read from `bin/cache/flutter.version.json`, or
  /// null when the SDK has not written it yet.
  String? get version {
    final file = File(p.join(root, 'bin', 'cache', 'flutter.version.json'));
    if (!file.existsSync()) return null;
    final Object? json;
    try {
      json = jsonDecode(file.readAsStringSync());
    } on FormatException {
      return null;
    }
    if (json is! Map<String, Object?>) return null;
    final version = json['frameworkVersion'];
    return version is String ? version : null;
  }
}

/// Parses `major.minor.patch` (ignoring pre-release suffixes) into a
/// comparable record, or null when [version] is not of that shape.
(int, int, int)? parseVersion(String version) {
  final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(version);
  if (match == null) return null;
  return (
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

/// True when [version] is at least [minimum] (both `x.y.z`).
bool isAtLeast(String version, (int, int, int) minimum) {
  final v = parseVersion(version);
  if (v == null) return false;
  if (v.$1 != minimum.$1) return v.$1 > minimum.$1;
  if (v.$2 != minimum.$2) return v.$2 > minimum.$2;
  return v.$3 >= minimum.$3;
}

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../shutter_exception.dart';

/// How to add the one dev dependency shutter needs.
const flutterTestHint = 'flutter pub add dev:flutter_test --sdk=flutter';

/// The Flutter project shutter operates on: the directory holding the
/// nearest `pubspec.yaml` at or above the working directory.
class Project({
  /// Absolute, normalised project root.
  required final String root,

  /// The pubspec `name:`, used to build `package:` URIs.
  required final String name,

  /// True when the pubspec declares `publish_to: none`.
  required final bool isApp,

  /// True when `flutter_test` is listed under `dev_dependencies`.
  required final bool hasFlutterTest,

  /// Package names under the pubspec's `dependencies:`.
  required final Set<String> dependencies,
}) {
  /// Walks up from [start] to the first directory containing a
  /// `pubspec.yaml` and reads the fields shutter needs.
  factory Project.find(String start) {
    var dir = p.normalize(p.absolute(start));
    while (!File(p.join(dir, 'pubspec.yaml')).existsSync()) {
      final parent = p.dirname(dir);
      if (parent == dir) {
        throw ShutterException(
          'no pubspec.yaml found at or above ${p.absolute(start)}.',
        );
      }
      dir = parent;
    }
    return Project.load(dir);
  }

  /// Reads `<root>/pubspec.yaml`.
  factory Project.load(String root) {
    final pubspecPath = p.join(root, 'pubspec.yaml');
    final Object? yaml;
    try {
      yaml = loadYaml(File(pubspecPath).readAsStringSync());
    } on YamlException catch (e) {
      throw ShutterException('$pubspecPath is not valid YAML: ${e.message}');
    }
    final name = yaml is YamlMap ? yaml['name'] : null;
    if (yaml is! YamlMap || name is! String) {
      throw ShutterException('$pubspecPath has no `name:`.');
    }
    final dependencies = yaml['dependencies'];
    final devDependencies = yaml['dev_dependencies'];
    return Project(
      root: root,
      name: name,
      isApp: yaml['publish_to']?.toString() == 'none',
      hasFlutterTest:
          devDependencies is YamlMap &&
          devDependencies.containsKey('flutter_test'),
      dependencies: {
        if (dependencies is YamlMap) ...dependencies.keys.cast<String>(),
      },
    );
  }

  String get libDir => p.join(root, 'lib');

  /// Written by `pub get`; absent until the project's packages resolve.
  String get packageConfigPath =>
      p.join(root, '.dart_tool', 'package_config.json');

  /// Root directory of package [name] as the project resolves it (direct
  /// or transitive), from `.dart_tool/package_config.json`; null when it
  /// is not resolved (or `pub get` has not run).
  String? packageRoot(String name) => _packageRoots[name];

  late final Map<String, String> _packageRoots = () {
    final config = File(packageConfigPath);
    if (!config.existsSync()) return const <String, String>{};
    final Object? json;
    try {
      json = jsonDecode(config.readAsStringSync());
    } on FormatException {
      return const <String, String>{};
    }
    final packages = json is Map<String, Object?> ? json['packages'] : null;
    if (packages is! List<Object?>) return const <String, String>{};
    final base = Uri.directory(p.dirname(config.path));
    return {
      for (final package in packages)
        if (package case {
          'name': final String name,
          'rootUri': final String rootUri,
        })
          name: p.normalize(base.resolve(rootUri).toFilePath()),
    };
  }();

  /// Shutter's working directory. Never committed.
  String get shutterDir => p.join(root, '.shutter');

  String get runsDir => p.join(shutterDir, 'runs');

  String get diffsDir => p.join(shutterDir, 'diffs');

  String get testDir => p.join(shutterDir, 'test');

  /// google_fonts files downloaded for rendering (see `doc/manual.md`).
  String get googleFontsDir => p.join(shutterDir, 'fonts', 'google_fonts');

  /// The conventional preview directory: `lib/src/preview/` for packages
  /// (keeps previews off the public API surface), `lib/preview/` for apps.
  /// An existing `lib/src/preview/` wins regardless of the pubspec.
  String get previewDir {
    final packageDir = p.join(libDir, 'src', 'preview');
    if (Directory(packageDir).existsSync() || !isApp) return packageDir;
    return p.join(libDir, 'preview');
  }

  /// `<previewDir>/shell.dart` when it exists.
  String? get shellPath {
    final path = p.join(previewDir, 'shell.dart');
    return File(path).existsSync() ? path : null;
  }

  /// Project-relative POSIX path of [absolutePath].
  String relative(String absolutePath) =>
      p.posix.joinAll(p.split(p.relative(absolutePath, from: root)));

  /// `package:` URI of a file under `lib/`.
  String packageUri(String absolutePath) {
    final rel = p.split(p.relative(absolutePath, from: libDir));
    return 'package:$name/${p.posix.joinAll(rel)}';
  }
}

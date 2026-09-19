import 'dart:io';

import 'package:shutter/src/version.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('the generated packageVersion matches pubspec.yaml '
      '(dart run build_runner build)', () {
    final pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    expect(packageVersion, pubspec['version']);
  });
}

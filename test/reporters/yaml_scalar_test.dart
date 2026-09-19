import 'package:shutter/src/reporters/yaml_scalar.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('plain when unambiguous, quoted otherwise; always reads back', () {
    const cases = {
      '/abs/run/a.0.png': '/abs/run/a.0.png',
      'lib/a.dart:3:4': 'lib/a.dart:3:4',
      'abc123.0': 'abc123.0',
      '0123.0': '"0123.0"',
      '.inf': '".inf"',
      '.nan': '".nan"',
      '.5': '".5"',
      'true': '"true"',
      'Name / with spaces': '"Name / with spaces"',
      'ends:': '"ends:"',
      'say "hi": #1': r'"say \"hi\": #1"',
      '': '""',
    };
    for (final MapEntry(key: value, value: expected) in cases.entries) {
      expect(yamlScalar(value), expected, reason: value);
      expect(
        (loadYaml('k: ${yamlScalar(value)}') as YamlMap)['k'],
        value,
        reason: value,
      );
    }
  });
}

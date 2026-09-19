import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// `skills/` ships in the package for `dart run skills get` and
/// `dart run skills add`, which require `<package>-<skill>` names and a
/// YAML frontmatter with `name`.
void main() {
  final skills = Directory('skills').listSync().whereType<Directory>().toList();

  test('there is a skill', () => expect(skills, isNotEmpty));

  for (final dir in skills) {
    final name = p.basename(dir.path);
    test('$name: named after the package, frontmatter matches', () {
      expect(name, startsWith('shutter-'));
      final content = File(p.join(dir.path, 'SKILL.md')).readAsStringSync();
      expect(content, startsWith('---\n'));
      final end = content.indexOf('---', 3);
      final frontmatter = loadYaml(content.substring(3, end)) as YamlMap;
      expect(frontmatter['name'], name);
      expect(frontmatter['description'], isA<String>());
      // The playbook stays in the binary, so the skill cannot drift from
      // the installed version.
      expect(content, contains('`shutter agent`'));
      expect(content.split('\n').length, lessThan(500));
    });
  }
}

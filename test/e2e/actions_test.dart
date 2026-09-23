@Tags(['e2e'])
library;

import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers.dart';
import 'e2e_helpers.dart';

void main() {
  test('actions change the shot; a target that matches none or two is an '
      'error', () async {
    final root = await exampleCopy();
    Future<(String, Map<String, Shot>)> shoot(List<String> args) =>
        shootIn(root, args);
    writeFiles(root, {
      'lib/preview/button_state_preview.dart': '''
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

@Preview(name: 'State / button', size: Size(200, 80))
Widget button() => Center(
  child: ElevatedButton(onPressed: () {}, child: const Text('Save')),
);

@Preview(name: 'State / two buttons', size: Size(200, 80))
Widget twoButtons() => Row(
  children: [
    TextButton(onPressed: () {}, child: const Text('Save')),
    TextButton(onPressed: () {}, child: const Text('Save')),
  ],
);
''',
    });
    const buttons = 'lib/preview/button_state_preview.dart';
    final (plain, _) = await shoot([buttons]);
    for (final action in [
      ['--press', 'text:Save'],
      ['--hover', 'type:ElevatedButton'],
      ['--focus', 'type:ElevatedButton'],
    ]) {
      final (run, shots) = await shoot([buttons, ...action]);
      final button = shots['State / button']!;
      expect(button.status, ShotStatus.ok, reason: '$action ${button.error}');
      expect(button.size, (200.0, 80.0));
      final two = shots['State / two buttons']!;
      expect(two.png, isNull);
      expect(two.at, startsWith('lib/preview/button_state_preview.dart:'));
      final diff = await shutter(root, ['diff', plain, run]);
      final report = loadYaml(diff.stdout) as YamlMap;
      expect(report['actions'], {
        'before': <Object?>[],
        'after': ['${action[0].substring(2)} ${action[1]}'],
      });
      final entry = (report['entries'] as YamlList).cast<YamlMap>().singleWhere(
        (e) => e['name'] == 'State / button',
      );
      expect(entry['status'], 'changed', reason: '$action');
    }
    final (_, missed) = await shoot([buttons, '--tap', 'text:Cancel']);
    expect(
      missed['State / button']!.error,
      'tap text:Cancel: no widget matches',
    );
    expect(
      missed['State / two buttons']!.error,
      'tap text:Cancel: no widget matches',
    );
    final (_, twice) = await shoot([buttons, '--press', 'text:Save']);
    expect(
      twice['State / two buttons']!.error,
      'press text:Save: 2 widgets match; name one',
    );
  });
}

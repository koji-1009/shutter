@Tags(['e2e'])
library;

import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers.dart';
import 'e2e_helpers.dart';

void main() {
  test(
    'actions change the shot; a target they cannot reach is an error',
    () async {
      final root = await exampleCopy();
      Future<(String, Map<String, Shot>)> shoot(List<String> args) =>
          shootIn(root, args);
      writeFiles(root, {
        'lib/preview/route_preview.dart': routePreview,
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
        final entry = (report['entries'] as YamlList)
            .cast<YamlMap>()
            .singleWhere((e) => e['name'] == 'State / button');
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
      writeFiles(root, {
        'lib/preview/unreachable_preview.dart': '''
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

@Preview(name: 'Ignored', size: Size(200, 80))
Widget ignored() => IgnorePointer(
  child: Center(
    child: ElevatedButton(onPressed: () {}, child: const Text('Hidden')),
  ),
);

@Preview(name: 'Plain', size: Size(200, 80))
Widget plain() => const Text('Plain');
''',
      });
      const unreachable = 'lib/preview/unreachable_preview.dart';
      final (_, ignored) = await shoot([unreachable, '--tap', 'text:Hidden']);
      expect(
        ignored['Ignored']!.error,
        startsWith(
          'tap text:Hidden: a pointer at its centre does not reach it',
        ),
      );
      expect(ignored['Ignored']!.at, 'lib/preview/unreachable_preview.dart:4');
      final (_, unfocusable) = await shoot([
        unreachable,
        '--focus',
        'text:Plain',
      ]);
      expect(
        unfocusable['Plain']!.error,
        'focus text:Plain: the widget cannot take focus',
      );

      // A tap that pushes a page covers the preview.
      const route = ['lib/preview/route_preview.dart', '--tap', 'text:Go'];
      final (_, covered) = await shoot(route);
      expect(covered['Route']!.png, isNull);
      expect(
        covered['Route']!.error,
        startsWith('the preview is no longer painted after the actions'),
      );

      // Taps run in order: the second finds what the first expanded.
      writeFiles(root, {
        'lib/preview/tile_state_preview.dart': '''
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

@Preview(name: 'State / tile', size: Size(240, 200))
Widget tile() => const Material(
  child: ExpansionTile(title: Text('More'), children: [_Agree()]),
);

class _Agree extends StatefulWidget {
  const _Agree();

  @override
  State<_Agree> createState() => _AgreeState();
}

class _AgreeState extends State<_Agree> {
  bool agreed = false;

  @override
  Widget build(BuildContext context) => Checkbox(
    value: agreed,
    onChanged: (value) => setState(() => agreed = value!),
  );
}
''',
      });
      const tile = 'lib/preview/tile_state_preview.dart';
      final (expanded, _) = await shoot([tile, '--tap', 'text:More']);
      final (checked, checkedShots) = await shoot([
        tile,
        '--tap',
        'text:More',
        '--tap',
        'type:Checkbox',
      ]);
      final agreed = checkedShots['State / tile']!;
      expect(agreed.status, ShotStatus.ok, reason: agreed.error);
      expect((await shutter(root, ['diff', expanded, checked])).exitCode, 1);
      final (_, reversed) = await shoot([
        tile,
        '--tap',
        'type:Checkbox',
        '--tap',
        'text:More',
      ]);
      expect(
        reversed['State / tile']!.error,
        'tap type:Checkbox: no widget matches',
      );
    },
  );
}

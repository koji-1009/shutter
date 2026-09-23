@Tags(['e2e'])
library;

import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'e2e_helpers.dart';

void main() {
  test('taps run in order: the second finds what the first expanded', () async {
    final root = await exampleCopy();
    Future<(String, Map<String, Shot>)> shoot(List<String> args) =>
        shootIn(root, args);
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
  });
}

@Tags(['e2e'])
library;

import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers.dart';
import 'e2e_helpers.dart';

void main() {
  test('--platform ios draws the app as iOS: defaultTargetPlatform, the '
      "theme's platform, and the back button", () async {
    final root = await exampleCopy();
    writeFiles(root, {
      'lib/preview/platform_preview.dart': '''
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

const _ios = Color(0xFF0000FF);
const _android = Color(0xFF00FF00);

Widget _box(bool ios) =>
    ColoredBox(color: ios ? _ios : _android, child: const SizedBox(width: 10, height: 10));

@Preview(name: 'Platform', size: Size(20, 10))
Widget platform() => Builder(
  builder: (context) => Row(
    children: [
      _box(defaultTargetPlatform == TargetPlatform.iOS),
      _box(Theme.of(context).platform == TargetPlatform.iOS),
    ],
  ),
);

@Preview(name: 'Back', size: Size(56, 56))
Widget back() => const Material(child: BackButtonIcon());
''',
    });
    const file = 'lib/preview/platform_preview.dart';

    (int, int, int) color(String run, Shot shot, int x, int y) {
      final image = img.decodePng(
        File(p.join(run, shot.png!)).readAsBytesSync(),
      )!;
      final pixel = image.getPixel(x, y);
      return (pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
    }

    final (android, androidShots) = await shootIn(root, [file]);
    final (ios, iosShots) = await shootIn(root, [file, '--platform', 'ios']);
    for (final shots in [androidShots, iosShots]) {
      for (final shot in shots.values) {
        expect(shot.status, ShotStatus.ok, reason: shot.error);
      }
    }
    for (final x in [5, 15]) {
      expect(color(android, androidShots['Platform']!, x * 2, 10), (0, 255, 0));
      expect(color(ios, iosShots['Platform']!, x * 2, 10), (0, 0, 255));
    }
    expect(RunManifest.read(ios).setup.platform, ShotPlatform.ios);
    expect(RunManifest.read(android).setup.platform, ShotPlatform.android);

    // The back button is iOS's chevron, not Android's arrow.
    final diff = await shutter(root, ['diff', android, ios]);
    expect(diff.exitCode, 1, reason: diff.stdout + diff.stderr);
    final report = loadYaml(diff.stdout) as YamlMap;
    expect(report['platform'], {'before': 'android', 'after': 'ios'});
    final entries = {
      for (final entry in (report['entries'] as YamlList).cast<YamlMap>())
        entry['name']: entry['status'],
    };
    expect(entries, {'Platform': 'changed', 'Back': 'changed'});
  });
}

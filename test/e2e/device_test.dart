@Tags(['e2e'])
library;

import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'e2e_helpers.dart';

/// [shot]'s PNG in [run].
img.Image _png(String run, Shot shot) =>
    img.decodePng(File(p.join(run, shot.png!)).readAsBytesSync())!;

/// The color of [image] at ([x], [y]).
(int, int, int) _color(img.Image image, int x, int y) {
  final pixel = image.getPixel(x, y);
  return (pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
}

void main() {
  final shared = sharedExample();

  test('--pixel-ratio draws the app at that ratio: the PNG, the view, the '
      'screen, and the semantics tree', () async {
    final root = await shared();
    File(p.join(root, 'lib/preview/ratio_preview.dart')).writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

@Preview(name: 'Ratio', size: Size(20, 10))
Widget ratio() => Builder(
  builder: (context) => ColoredBox(
    color: MediaQuery.devicePixelRatioOf(context) == 3
        ? const Color(0xFF0000FF)
        : const Color(0xFF00FF00),
  ),
);
''');
    const file = 'lib/preview/ratio_preview.dart';
    final (plain, plainShots) = await shootIn(root, [file]);
    final (dense, denseShots) = await shootIn(root, [
      file,
      '--pixel-ratio',
      '3',
    ]);
    final (screen, screenShots) = await shootIn(root, [
      file,
      '--pixel-ratio',
      '3',
      '--capture',
      'screen',
      '--viewport',
      '30x20',
    ]);
    for (final shots in [plainShots, denseShots, screenShots]) {
      expect(
        shots['Ratio']!.status,
        ShotStatus.ok,
        reason: shots['Ratio']!.error,
      );
    }
    final plainPng = _png(plain, plainShots['Ratio']!);
    expect((plainPng.width, plainPng.height), (40, 20));
    expect(_color(plainPng, 5, 5), (0, 255, 0));
    final densePng = _png(dense, denseShots['Ratio']!);
    expect((densePng.width, densePng.height), (60, 30));
    expect(_color(densePng, 5, 5), (0, 0, 255));
    final screenPng = _png(screen, screenShots['Ratio']!);
    expect((screenPng.width, screenPng.height), (90, 60));
    // The shot's size stays logical.
    expect(denseShots['Ratio']!.size, (20.0, 10.0));
    expect(RunManifest.read(dense).setup.pixelRatio, 3);
    expect(RunManifest.read(plain).setup.pixelRatio, defaultPixelRatio);

    final tree = await shutter(root, ['semantics', file, '--pixel-ratio', '3']);
    expect(tree.exitCode, 0, reason: tree.stdout + tree.stderr);
    final treeRun = (loadYaml(tree.stdout) as YamlMap)['run'] as String;
    final treePng = _png(treeRun, RunManifest.read(treeRun).shots.single);
    expect((treePng.width, treePng.height), (60, 30));

    final diff = await shutter(root, ['diff', plain, dense]);
    expect(diff.exitCode, 1, reason: diff.stdout + diff.stderr);
    final report = loadYaml(diff.stdout) as YamlMap;
    expect(report['pixel_ratio'], {'before': 2, 'after': 3});
  });
}

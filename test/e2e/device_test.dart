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

    // 25 at 2.2 is 55.00000000000001 in binary; the PNG is still 55 wide.
    File(p.join(root, 'lib/preview/odd_ratio_preview.dart'))
        .writeAsStringSync('''
import 'package:flutter/widgets.dart';
import 'package:flutter/widget_previews.dart';

@Preview(name: 'Odd', size: Size(25, 10))
Widget odd() => const ColoredBox(color: Color(0xFF00FF00));
''');
    const odd = 'lib/preview/odd_ratio_preview.dart';
    final (oddRun, oddShots) = await shootIn(root, [
      odd,
      '--pixel-ratio',
      '2.2',
    ]);
    final (oddScreen, oddScreenShots) = await shootIn(root, [
      odd,
      '--pixel-ratio',
      '2.2',
      '--capture',
      'screen',
      '--viewport',
      '50x20',
    ]);
    final oddTree = await shutter(root, [
      'semantics',
      odd,
      '--pixel-ratio',
      '2.2',
    ]);
    expect(oddTree.exitCode, 0, reason: oddTree.stdout + oddTree.stderr);
    final oddTreeRun = (loadYaml(oddTree.stdout) as YamlMap)['run'] as String;
    for (final (png, size) in [
      (_png(oddRun, oddShots['Odd']!), (55, 22)),
      (_png(oddScreen, oddScreenShots['Odd']!), (110, 44)),
      (_png(oddTreeRun, RunManifest.read(oddTreeRun).shots.single), (55, 22)),
    ]) {
      expect((png.width, png.height), size);
    }
    expect(_color(_png(oddRun, oddShots['Odd']!), 54, 21), (0, 255, 0));
  });

  test('--safe-area pads the view: SafeArea keeps out of it, and a keyboard '
      'absorbs the bottom inset from the padding only', () async {
    final root = await shared();
    File(p.join(root, 'lib/preview/safe_area_preview.dart'))
        .writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

@Preview(name: 'SafeArea', size: Size(20, 40))
Widget safeArea() => const ColoredBox(
  color: Color(0xFFFF0000),
  child: SafeArea(child: ColoredBox(color: Color(0xFF00FF00))),
);

@Preview(name: 'ViewPadding', size: Size(20, 10))
Widget viewPadding() => Builder(
  builder: (context) => ColoredBox(
    color: MediaQuery.viewPaddingOf(context) == const EdgeInsets.only(top: 10, bottom: 5)
        ? const Color(0xFF0000FF)
        : const Color(0xFF00FF00),
  ),
);
''');
    const file = 'lib/preview/safe_area_preview.dart';
    const red = (255, 0, 0);
    const green = (0, 255, 0);
    final (plain, plainShots) = await shootIn(root, [file]);
    final (padded, paddedShots) = await shootIn(root, [
      file,
      '--safe-area',
      '10,5',
    ]);
    final (typing, typingShots) = await shootIn(root, [
      file,
      '--safe-area',
      '10,5',
      '--keyboard',
      '20',
    ]);
    for (final shots in [plainShots, paddedShots, typingShots]) {
      for (final shot in shots.values) {
        expect(shot.status, ShotStatus.ok, reason: shot.error);
      }
    }
    // Rows at 2x: the top inset ends at 20, the bottom one starts at 70.
    final plainPng = _png(plain, plainShots['SafeArea']!);
    expect(
      [
        for (final y in [5, 40, 75]) _color(plainPng, 5, y),
      ],
      [green, green, green],
    );
    final paddedPng = _png(padded, paddedShots['SafeArea']!);
    expect(
      [
        for (final y in [5, 40, 75]) _color(paddedPng, 5, y),
      ],
      [red, green, red],
    );
    final typingPng = _png(typing, typingShots['SafeArea']!);
    expect(
      [
        for (final y in [5, 40, 75]) _color(typingPng, 5, y),
      ],
      [red, green, green],
    );
    for (final (run, shots) in [(padded, paddedShots), (typing, typingShots)]) {
      expect(_color(_png(run, shots['ViewPadding']!), 5, 5), (0, 0, 255));
    }
    expect(RunManifest.read(padded).setup.safeArea, (10.0, 5.0));
    expect(RunManifest.read(plain).setup.safeArea, isNull);

    final diff = await shutter(root, ['diff', plain, padded]);
    expect(diff.exitCode, 1, reason: diff.stdout + diff.stderr);
    final report = loadYaml(diff.stdout) as YamlMap;
    expect(report['safe_area'], {
      'before': 'none',
      'after': [10, 5],
    });
  });

  test('--brightness and --text-scale reach every preview that sets none; '
      "a preview's own win", () async {
    final root = await shared();
    File(p.join(root, 'lib/preview/appearance_preview.dart'))
        .writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

Widget _box(bool on) => ColoredBox(
  color: on ? const Color(0xFF0000FF) : const Color(0xFF00FF00),
  child: const SizedBox(width: 10, height: 10),
);

Widget _appearance() => Builder(
  builder: (context) => Row(
    children: [
      _box(MediaQuery.platformBrightnessOf(context) == Brightness.dark),
      _box(MediaQuery.textScalerOf(context).scale(10) == 13),
    ],
  ),
);

@Preview(name: 'Device', size: Size(20, 10))
Widget device() => _appearance();

@Preview(
  name: 'Own',
  size: Size(20, 10),
  brightness: Brightness.light,
  textScaleFactor: 1,
)
Widget own() => _appearance();
''');
    const file = 'lib/preview/appearance_preview.dart';
    const on = (0, 0, 255);
    const off = (0, 255, 0);
    final (plain, plainShots) = await shootIn(root, [file]);
    final (set, setShots) = await shootIn(root, [
      file,
      '--brightness',
      'dark',
      '--text-scale',
      '1.3',
    ]);
    for (final shots in [plainShots, setShots]) {
      for (final shot in shots.values) {
        expect(shot.status, ShotStatus.ok, reason: shot.error);
      }
    }
    (int, int, int) color(String run, Shot shot, int x) =>
        _color(_png(run, shot), x, 10);
    expect(
      [
        color(plain, plainShots['Device']!, 10),
        color(plain, plainShots['Device']!, 30),
      ],
      [off, off],
    );
    expect(
      [
        color(set, setShots['Device']!, 10),
        color(set, setShots['Device']!, 30),
      ],
      [on, on],
    );
    expect(
      [color(set, setShots['Own']!, 10), color(set, setShots['Own']!, 30)],
      [off, off],
    );
    final setup = RunManifest.read(set).setup;
    expect((setup.brightness, setup.textScale), (ShotBrightness.dark, 1.3));

    final diff = await shutter(root, ['diff', plain, set]);
    expect(diff.exitCode, 1, reason: diff.stdout + diff.stderr);
    final report = loadYaml(diff.stdout) as YamlMap;
    expect(report['brightness'], {'before': 'light', 'after': 'dark'});
    expect(report['text_scale'], {'before': 1, 'after': 1.3});
    final entries = {
      for (final entry in (report['entries'] as YamlList).cast<YamlMap>())
        entry['name']: entry['status'],
    };
    expect(entries, {'Device': 'changed', 'Own': 'unchanged'});
  });

  test("--locale is the device's: the platform reports it, and a preview's "
      'localizations without a locale resolve to it', () async {
    final root = await shared();
    File(p.join(root, 'lib/preview/locale_preview.dart')).writeAsStringSync('''
import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';

Widget _box(bool on) => ColoredBox(
  color: on ? const Color(0xFF0000FF) : const Color(0xFF00FF00),
  child: const SizedBox(width: 10, height: 10),
);

PreviewLocalizationsData englishOrJapanese() => const PreviewLocalizationsData(
  supportedLocales: [Locale('en'), Locale('ja')],
  localizationsDelegates: [DefaultWidgetsLocalizations.delegate],
);

@Preview(name: 'Platform', size: Size(10, 10))
Widget platform() => Builder(
  builder: (context) => _box(
    View.of(context).platformDispatcher.locale == const Locale('ja', 'JP'),
  ),
);

@Preview(name: 'Resolved', size: Size(10, 10), localizations: englishOrJapanese)
Widget resolved() => Builder(
  builder: (context) =>
      _box(Localizations.localeOf(context).languageCode == 'ja'),
);
''');
    const file = 'lib/preview/locale_preview.dart';
    final (plain, plainShots) = await shootIn(root, [file]);
    final (japanese, japaneseShots) = await shootIn(root, [
      file,
      '--locale',
      'ja-JP',
    ]);
    for (final shots in [plainShots, japaneseShots]) {
      for (final shot in shots.values) {
        expect(shot.status, ShotStatus.ok, reason: shot.error);
      }
    }
    for (final name in ['Platform', 'Resolved']) {
      expect(_color(_png(plain, plainShots[name]!), 10, 10), (0, 255, 0));
      expect(_color(_png(japanese, japaneseShots[name]!), 10, 10), (0, 0, 255));
    }
    expect(RunManifest.read(japanese).setup.locale, 'ja-JP');

    final diff = await shutter(root, ['diff', plain, japanese]);
    expect(diff.exitCode, 1, reason: diff.stdout + diff.stderr);
    final report = loadYaml(diff.stdout) as YamlMap;
    expect(report['locale'], {'before': 'default', 'after': 'ja-JP'});
  });
}

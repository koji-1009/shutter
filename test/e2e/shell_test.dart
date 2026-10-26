@Tags(['e2e'])
library;

import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'e2e_helpers.dart';

void main() {
  test('the init shell compiles; size and brightness apply', () async {
    final root = await exampleCopy();
    Directory(p.join(root, 'lib', 'preview')).deleteSync(recursive: true);
    final init = await shutter(root, ['init']);
    expect(init.exitCode, 0);
    writeFiles(root, {
      'lib/preview/templated_preview.dart': '''
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../ui/button.dart';
import '../ui/settings_page.dart';

@Preview(name: 'Settings / dark', size: Size(390, 844), brightness: .dark)
Widget settings() => const SettingsPage();

@Preview(name: 'Button', size: Size(200, 56))
Widget button() => const PrimaryButton(label: 'OK');

@Preview(name: 'Button / own height', size: Size(200, double.infinity))
Widget buttonOwnHeight() => const PrimaryButton(label: 'OK');

@Preview(name: 'Column / own height', size: Size(200, double.infinity))
Widget column() => const Column(children: [SizedBox(height: 40)]);

@Preview(name: 'Taller than the viewport', size: Size(200, double.infinity))
Widget tall() => const ColoredBox(
  color: Color(0xFF0000FF),
  child: SizedBox(height: 900),
);
''',
    });
    final analyze = await Process.run(flutter, [
      'analyze',
      'lib/preview',
    ], workingDirectory: root);
    expect(analyze.exitCode, 0, reason: '${analyze.stdout}${analyze.stderr}');
    final result = await shutter(root, [
      'shot',
      'lib/preview/templated_preview.dart',
    ]);
    expect(result.exitCode, 0, reason: result.stdout + result.stderr);
    final shots = {
      for (final s in RunManifest.read(lastRun(root)).shots) s.name: s,
    };
    expect(shots.keys, {
      'Settings / dark',
      'Button',
      'Button / own height',
      'Column / own height',
      'Taller than the viewport',
    });
    expect(shots['Settings / dark']!.size, (390.0, 844.0));
    expect(shots['Settings / dark']!.brightness, 'dark');
    expect(shots['Button']!.size, (200.0, 56.0));
    // An infinite height (a dart:core name in the annotation) is the
    // preview's own, as in a scrolling list: a Column does not stretch to
    // the viewport, and a taller preview is painted to its bottom.
    expect(shots['Button / own height']!.size, (200.0, 52.0));
    expect(shots['Column / own height']!.size, (200.0, 40.0));
    final tall = shots['Taller than the viewport']!;
    expect(tall.size, (200.0, 900.0));
    final image = img.decodePng(
      File(p.join(lastRun(root), tall.png!)).readAsBytesSync(),
    )!;
    expect((image.width, image.height), (400, 1800));
    final bottom = image.getPixel(200, 1799);
    expect((bottom.r, bottom.g, bottom.b, bottom.a), (0, 0, 255, 255));
  });

  test('a shell without Material gets none from shutter', () async {
    final root = await exampleCopy();
    writeFiles(root, {
      'lib/preview/shell.dart': '''
import 'package:flutter/widgets.dart';

Widget shell(Widget child) => WidgetsApp(
  color: const Color(0xFFFFFFFF),
  debugShowCheckedModeBanner: false,
  builder: (context, _) => child,
);
''',
      'lib/preview/plain_preview.dart': '''
import 'package:flutter/material.dart' show ListTile;
import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';

@Preview(name: 'Plain / text', size: Size(200, 40))
Widget plainText() => const Text('日本語 plain');

@Preview(name: 'Plain / list tile', size: Size(200, 56))
Widget plainTile() => const ListTile(title: Text('x'));
''',
    });
    final result = await shutter(root, [
      'shot',
      'lib/preview/plain_preview.dart',
    ]);
    expect(result.exitCode, 2, reason: result.stdout + result.stderr);
    final shots = {
      for (final s in RunManifest.read(lastRun(root)).shots) s.name: s,
    };
    expect(shots['Plain / text']!.status, ShotStatus.ok);
    expect(shots['Plain / list tile']!.error, contains('No Material widget'));
  });

  test(
    '--shell outside lib/ compiles and replaces the preview dir shell',
    () async {
      final root = await exampleCopy();
      writeFiles(root, {
        // No Material, unlike the example's lib/preview/shell.dart.
        '.dart_tool/shutter/shell.dart': '''
import 'package:flutter/widgets.dart';

Widget shell(Widget child) => WidgetsApp(
  color: const Color(0xFFFFFFFF),
  debugShowCheckedModeBanner: false,
  builder: (context, _) => child,
);
''',
        'lib/preview/tile_preview.dart': '''
import 'package:flutter/material.dart' show ListTile;
import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';

@Preview(name: 'Tile', size: Size(200, 56))
Widget tile() => const ListTile(title: Text('x'));
''',
      });
      final result = await shutter(root, [
        'shot',
        '--shell',
        '.dart_tool/shutter/shell.dart',
        'lib/preview/tile_preview.dart',
      ]);
      expect(result.exitCode, 2, reason: result.stdout + result.stderr);
      final manifest = RunManifest.read(lastRun(root));
      expect(manifest.shots.single.error, contains('No Material widget'));
      expect(manifest.shell?.path, '.dart_tool/shutter/shell.dart');
    },
  );

  test(
    'a style that inherits nothing still falls back to host fonts',
    () async {
      final root = await exampleCopy();
      // CupertinoAlertDialog's title style is `inherit: false` and names the
      // Cupertino system font, so neither the default text style nor a theme
      // reaches it. Emoji, rather than CJK, because the CI host has emoji
      // fonts only.
      writeFiles(root, {
        'lib/preview/dialog_preview.dart': '''
import 'package:flutter/cupertino.dart';
import 'package:flutter/widget_previews.dart';

Widget emojiDialog() => const CupertinoAlertDialog(title: Text('🍎🍊🍋'));

@Preview(name: 'Dialog', size: Size(320, 160))
Widget dialog() => emojiDialog();

/// A package's font: the style prefixes its fallback families with the
/// package.
@Preview(name: 'Package font', size: Size(320, 40))
Widget packageFont() => const Text(
  '🍎🍊🍋',
  style: TextStyle(fontFamily: 'Brand', package: 'brand_fonts'),
);

/// Text built while the view is laid out, in the frame before the
/// capture: there is no room for it until then.
@Preview(name: 'Built in layout', size: Size(320, 40))
Widget builtInLayout() => TweenAnimationBuilder<double>(
  tween: Tween(begin: 0, end: 40),
  duration: const Duration(milliseconds: 300),
  builder: (_, height, _) => Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (_, constraints) => constraints.maxHeight < 40
            ? const SizedBox.shrink()
            : const Text(
                '🍎🍊🍋',
                style: TextStyle(
                  inherit: false,
                  fontSize: 14,
                  color: Color(0xFF000000),
                ),
              ),
      ),
    ),
  ),
);
''',
        'lib/preview/show_preview.dart': '''
import 'package:flutter/cupertino.dart';
import 'package:flutter/widget_previews.dart';

import 'dialog_preview.dart';

@Preview(name: 'Shown', size: Size(320, 240))
Widget shown() => Builder(
  builder: (context) => GestureDetector(
    onTap: () => showCupertinoDialog<void>(
      context: context,
      builder: (_) => emojiDialog(),
    ),
    child: const Text('open'),
  ),
);
''',
      });
      // Colored pixels: the emoji font drew the glyphs; the test font's
      // boxes are in the black title color.
      int colored(String run, Shot shot) {
        final image = img.decodePng(
          File(p.join(run, shot.png!)).readAsBytesSync(),
        )!;
        var count = 0;
        for (final pixel in image) {
          final channels = [pixel.r, pixel.g, pixel.b];
          if (channels.reduce(max) - channels.reduce(min) > 64) count++;
        }
        return count;
      }

      final (run, shots) = await shootIn(root, [
        'lib/preview/dialog_preview.dart',
      ]);
      for (final name in ['Dialog', 'Package font', 'Built in layout']) {
        expect(shots[name]!.status, ShotStatus.ok, reason: name);
        expect(colored(run, shots[name]!), greaterThan(0), reason: name);
      }
      final (screenRun, screenShots) = await shootIn(root, [
        'lib/preview/show_preview.dart',
        '--tap',
        'text:open',
        '--capture',
        'screen',
      ]);
      expect(screenShots['Shown']!.status, ShotStatus.ok);
      expect(colored(screenRun, screenShots['Shown']!), greaterThan(0));
    },
  );

  test(
    'scripts beyond CJK fall back to host fonts',
    () async {
      final root = await exampleCopy();
      // The same letters in two orders: boxes draw them alike, glyphs
      // differently. Han characters only Simplified Chinese has.
      const scripts = {
        'Hans': ('这们说', '说这们'),
        'Hangul': ('한국어', '어한국'),
        'Thai': ('กขค', 'คกข'),
        'Arabic': ('عرب', 'برع'),
        'Hebrew': ('אבג', 'גאב'),
        'Devanagari': ('कखग', 'गकख'),
      };
      writeFiles(root, {
        'lib/preview/scripts_preview.dart': [
          "import 'package:flutter/widget_previews.dart';",
          "import 'package:flutter/widgets.dart';",
          for (final MapEntry(key: script, value: (a, b)) in scripts.entries)
            for (final (i, text) in [(1, a), (2, b)]) ...[
              "@Preview(name: '$script $i', size: Size(200, 40))",
              "Widget ${script.toLowerCase()}$i() => const Text('$text');",
            ],
        ].join('\n'),
      });
      final (run, shots) = await shootIn(root, [
        'lib/preview/scripts_preview.dart',
      ]);
      Digest png(String name) => sha256.convert(
        File(p.join(run, shots[name]!.png!)).readAsBytesSync(),
      );
      final boxes = [
        for (final script in scripts.keys)
          if (png('$script 1') == png('$script 2')) script,
      ];
      expect(boxes, isEmpty, reason: 'rendered as boxes');
    },
    // The CI host has emoji fonts only.
    skip: Platform.isMacOS ? false : 'needs the macOS host fonts',
  );

  test('a project on material_ui gets a material_ui default shell', () async {
    final root = await exampleCopy();
    File(p.join(root, 'lib', 'preview', 'shell.dart')).deleteSync();
    final add = await Process.run(flutter, [
      'pub',
      'add',
      'material_ui',
    ], workingDirectory: root);
    expect(add.exitCode, 0, reason: '${add.stdout}${add.stderr}');
    final result = await shutter(root, [
      'shot',
      '--widget',
      'ElevatedButton(onPressed: () {}, child: const Text("日本語"))',
      '--import',
      'package:material_ui/material_ui.dart',
      '--size',
      '200x56',
    ]);
    // A material_ui button needs material_ui's Material above it.
    expect(result.exitCode, 0, reason: result.stdout + result.stderr);
    expect(RunManifest.read(lastRun(root)).shots.single.status, ShotStatus.ok);
  });
}

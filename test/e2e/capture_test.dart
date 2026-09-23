@Tags(['e2e'])
library;

import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'e2e_helpers.dart';

/// A dropdown whose menu opens below its 60-high preview.
const menuPreview = '''
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

@Preview(name: 'State / menu', size: Size(200, 60))
Widget menu() => Align(
  alignment: Alignment.topLeft,
  child: DropdownButton<String>(
    value: 'a',
    items: const [
      DropdownMenuItem(value: 'a', child: Text('Alpha')),
      DropdownMenuItem(value: 'b', child: Text('Beta')),
    ],
    onChanged: (_) {},
  ),
);
''';

void main() {
  test(
    '--capture screen draws the viewport at the scale of the preview',
    () async {
      final root = await exampleCopy();
      writeFiles(root, {
        'lib/preview/box_preview.dart': '''
import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';

@Preview(name: 'Box', size: Size(100, 50))
Widget box() => const ColoredBox(color: Color(0xFF0000FF));
''',
      });
      // The screen is drawn at the same scale as the preview: a 100x50 box
      // at the top left of a 200x100 viewport fills a quarter of the image.
      final (boxRun, boxShots) = await shootIn(root, [
        'lib/preview/box_preview.dart',
        '--capture',
        'screen',
        '--viewport',
        '200x100',
      ]);
      final boxImage = img.decodePng(
        File(p.join(boxRun, boxShots['Box']!.png!)).readAsBytesSync(),
      )!;
      expect((boxImage.width, boxImage.height), (400, 200));
      bool blue(int x, int y) {
        final pixel = boxImage.getPixel(x, y);
        return (pixel.r, pixel.g, pixel.b) == (0, 0, 255);
      }

      expect(blue(199, 99), isTrue);
      expect(blue(201, 50), isFalse);
      expect(blue(50, 101), isFalse);
    },
  );

  test('--capture screen holds a menu that opens below the preview', () async {
    final root = await exampleCopy();
    Future<(String, Map<String, Shot>)> shoot(List<String> args) =>
        shootIn(root, args);
    writeFiles(root, {'lib/preview/menu_state_preview.dart': menuPreview});
    // The menu's second item lies below the 60-high preview, in the
    // screen only.
    const menu = 'lib/preview/menu_state_preview.dart';
    final screen = ['--capture', 'screen', '--viewport', '200x240'];
    final (closed, closedShots) = await shoot([menu, ...screen]);
    expect(closedShots['State / menu']!.size, (200.0, 240.0));
    final (open, openShots) = await shoot([
      menu,
      ...screen,
      '--tap',
      'type:DropdownButton<String>',
    ]);
    final opened = openShots['State / menu']!;
    expect(opened.status, ShotStatus.ok, reason: opened.error);
    final image = img.decodePng(
      File(p.join(open, opened.png!)).readAsBytesSync(),
    )!;
    expect((image.width, image.height), (400, 480));
    final closedImage = img.decodePng(
      File(p.join(closed, closedShots['State / menu']!.png!)).readAsBytesSync(),
    )!;
    var differing = 0;
    for (var y = 120; y < 480; y++) {
      for (var x = 0; x < 400; x++) {
        final (a, b) = (image.getPixel(x, y), closedImage.getPixel(x, y));
        if ((a.r, a.g, a.b, a.a) != (b.r, b.g, b.b, b.a)) differing++;
      }
    }
    expect(differing, greaterThan(0));
  });

  test('--keyboard lays out a Scaffold, and a layout reading the inset, above '
      'the keyboard; the screen shows what the app paints under it', () async {
    final root = await exampleCopy();
    writeFiles(root, {
      'lib/preview/keyboard_preview.dart': '''
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

const _bar = ColoredBox(
  color: Color(0xFFFF0000),
  child: SizedBox(width: double.infinity, height: 20),
);

@Preview(name: 'Keyboard / scaffold', size: Size(200, 300))
Widget scaffold() => const Scaffold(
  backgroundColor: Color(0xFF00FF00),
  body: Column(children: [Spacer(), _bar]),
);

@Preview(name: 'Keyboard / not resized', size: Size(200, 300))
Widget notResized() => const Scaffold(
  resizeToAvoidBottomInset: false,
  body: Column(children: [Spacer(), _bar]),
);

@Preview(name: 'Keyboard / own layout', size: Size(200, 300))
Widget own() => Builder(
  builder: (context) => Padding(
    padding: MediaQuery.viewInsetsOf(context),
    child: const Column(children: [Spacer(), _bar]),
  ),
);
''',
    });
    const file = 'lib/preview/keyboard_preview.dart';
    const red = (255, 0, 0);
    final plain = await shootIn(root, [file]);
    final typing = await shootIn(root, [file, '--keyboard', '100']);
    final screen = await shootIn(root, [
      file,
      '--keyboard',
      '100',
      '--capture',
      'screen',
      '--viewport',
      '200x300',
    ]);
    expect(RunManifest.read(typing.$1).setup.keyboard, 100);
    (int, int, int) color((String, Map<String, Shot>) run, String name, int y) {
      final shot = run.$2[name]!;
      expect(shot.status, ShotStatus.ok, reason: shot.error);
      final image = img.decodePng(
        File(p.join(run.$1, shot.png!)).readAsBytesSync(),
      )!;
      expect((image.width, image.height), (400, 600), reason: name);
      final pixel = image.getPixel(200, y);
      return (pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
    }

    // The bar ends at the bottom of the 300-high preview, and above a
    // 100-high keyboard with --keyboard.
    for (final name in ['Keyboard / scaffold', 'Keyboard / own layout']) {
      expect(color(plain, name, 580), red, reason: name);
      expect(color(plain, name, 380), isNot(red), reason: name);
      for (final run in [typing, screen]) {
        expect(color(run, name, 380), red, reason: name);
        expect(color(run, name, 580), isNot(red), reason: name);
      }
    }
    // A Scaffold that does not resize keeps its bar under the keyboard.
    for (final run in [plain, typing]) {
      expect(color(run, 'Keyboard / not resized', 580), red);
      expect(color(run, 'Keyboard / not resized', 380), isNot(red));
    }
    // No keyboard is drawn: under it, the screen holds what the app paints
    // there, the Scaffold's background.
    expect(color(screen, 'Keyboard / scaffold', 500), (0, 255, 0));
  });

  test('--capture screen holds a pushed page; --settle lets its transition '
      'end', () async {
    final root = await exampleCopy();
    writeFiles(root, {'lib/preview/route_preview.dart': routePreview});
    // A page a tap pushes is in the screen; its transition takes 450 ms,
    // still under way at the default 300, over by 700.
    const route = ['lib/preview/route_preview.dart', '--tap', 'text:Go'];
    Future<String> settled(String ms) async => (await shootIn(root, [
      ...route,
      '--capture',
      'screen',
      '--settle',
      ms,
    ])).$1;
    final at300 = await settled('300');
    final pushed = RunManifest.read(at300).shots.single;
    expect(pushed.status, ShotStatus.ok, reason: pushed.error);
    expect(pushed.size, (200.0, 100.0));
    final (at700, at800) = (await settled('700'), await settled('800'));
    expect((await shutter(root, ['diff', at300, at700])).exitCode, 1);
    expect((await shutter(root, ['diff', at700, at800])).exitCode, 0);
  });
}

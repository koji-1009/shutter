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
  test('--capture screen holds the viewport and what opens above the '
      'preview', () async {
    final root = await exampleCopy();
    Future<(String, Map<String, Shot>)> shoot(List<String> args) =>
        shootIn(root, args);
    writeFiles(root, {
      'lib/preview/menu_state_preview.dart': menuPreview,
      'lib/preview/route_preview.dart': routePreview,
      'lib/preview/box_preview.dart': '''
import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';

@Preview(name: 'Box', size: Size(100, 50))
Widget box() => const ColoredBox(color: Color(0xFF0000FF));
''',
    });
    // The screen is drawn at the same scale as the preview: a 100x50 box
    // at the top left of a 200x100 viewport fills a quarter of the image.
    final (boxRun, boxShots) = await shoot([
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

    // A page a tap pushes is in the screen; its transition takes 450 ms,
    // still under way at the default 300, over by 700.
    const route = ['lib/preview/route_preview.dart', '--tap', 'text:Go'];
    Future<String> settled(String ms) async =>
        (await shoot([...route, '--capture', 'screen', '--settle', ms])).$1;
    final at300 = await settled('300');
    final pushed = RunManifest.read(at300).shots.single;
    expect(pushed.status, ShotStatus.ok, reason: pushed.error);
    expect(pushed.size, (200.0, 100.0));
    final (at700, at800) = (await settled('700'), await settled('800'));
    expect((await shutter(root, ['diff', at300, at700])).exitCode, 1);
    expect((await shutter(root, ['diff', at700, at800])).exitCode, 0);
  });
}

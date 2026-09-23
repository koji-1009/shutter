@Tags(['e2e'])
library;

import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'e2e_helpers.dart';

void main() {
  test('a target the actions cannot reach is an error; a pushed page covers '
      'the preview', () async {
    final root = await exampleCopy();
    Future<(String, Map<String, Shot>)> shoot(List<String> args) =>
        shootIn(root, args);
    writeFiles(root, {
      'lib/preview/route_preview.dart': routePreview,
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
      startsWith('tap text:Hidden: a pointer at its centre does not reach it'),
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
  });
}

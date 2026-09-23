@Tags(['e2e'])
library;

import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'e2e_helpers.dart';

void main() {
  test('a MultiPreview whose previews throw is an error shot', () async {
    final root = await exampleCopy();
    writeFiles(root, {
      'lib/preview/boom_preview.dart': '''
import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';

final class Boom extends MultiPreview {
  const Boom();

  @override
  List<Preview> get previews => throw StateError('boom');
}

@Boom()
Widget boom() => const Text('x');
''',
    });
    await shutter(root, ['shot', 'lib/preview/boom_preview.dart']);
    expect(
      RunManifest.read(lastRun(root)).shots.single.error,
      contains('boom'),
    );
  });

  test('a static const annotation is shot; a sealed class is not; a '
      'non-widget is an error', () async {
    final root = await exampleCopy();
    writeFiles(root, {
      'lib/preview/resolved_preview.dart': '''
import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';

sealed class Shape extends StatelessWidget {
  @Preview(name: 'Sealed')
  const Shape();
}

class Card extends StatelessWidget {
  const Card();

  static const kPreview = Preview(name: 'Static const', size: Size(80, 40));

  @kPreview
  static Widget viaStatic() => const Card();

  @override
  Widget build(BuildContext context) => const Text('card');
}

@Preview(name: 'Not a widget', size: Size(80, 40))
int notAWidget() => 1;
''',
    });
    await shutter(root, ['shot', 'lib/preview/resolved_preview.dart']);
    final resolved = {
      for (final s in RunManifest.read(lastRun(root)).shots) s.name: s,
    };
    expect(resolved.keys, {'Static const', 'Not a widget'});
    expect(resolved['Static const']!.status, ShotStatus.ok);
    expect(
      resolved['Not a widget']!.at,
      startsWith('lib/preview/resolved_preview.dart:'),
    );
  });

  test("a library's class that shadows a Flutter one compiles", () async {
    final root = await exampleCopy();
    writeFiles(root, {
      'lib/preview/shadow_preview.dart': '''
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

/// Shadows Material's Badge, as the library is allowed to.
class Badge extends StatelessWidget {
  @Preview(name: 'Shadow / Badge', size: Size(80, 40))
  const Badge({super.key});

  @override
  Widget build(BuildContext context) => const Text('own');
}
''',
    });
    final shadow = await shutter(root, [
      'shot',
      'lib/preview/shadow_preview.dart',
    ]);
    expect(shadow.exitCode, 0, reason: shadow.stdout + shadow.stderr);
  });
}

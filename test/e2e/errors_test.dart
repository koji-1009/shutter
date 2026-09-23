@Tags(['e2e'])
library;

import 'dart:io';

import 'package:shutter/src/cli/context.dart';
import 'package:shutter/src/engine/flutter_test_engine.dart';
import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'e2e_helpers.dart';

void main() {
  test('a file that does not compile makes every shot an error', () async {
    final root = await exampleCopy();
    writeFiles(root, {
      'lib/preview/broken_preview.dart': '''
import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';

@Preview(name: 'Broken')
Widget broken() => const DoesNotExist();
''',
    });
    final result = await shutter(root, [
      'shot',
      'lib/preview/button_preview.dart',
      'lib/preview/broken_preview.dart',
    ]);
    expect(result.exitCode, 2);
    final shots = RunManifest.read(lastRun(root)).shots;
    expect(shots, hasLength(5));
    for (final shot in shots) {
      expect(shot.status, ShotStatus.error);
      expect(shot.error, contains('broken_preview.dart'));
      expect(shot.error, contains('Error:'));
    }
  });

  test(
    'google_fonts that cannot be downloaded make the shot an error',
    () async {
      final root = await exampleCopy();
      final result = await runCli(
        ['shot', 'lib/preview/google_fonts_preview.dart'],
        ShutterContext(
          workingDirectory: root,
          engineFactory: (sdk) => FlutterTestEngine(
            sdk: sdk,
            fetchFont: (_) async => throw const SocketException('offline'),
          ),
        ),
      );
      expect(result.exitCode, 2);
      final shot = RunManifest.read(lastRun(root)).shots.single;
      expect(shot.status, ShotStatus.error);
      expect(
        shot.error,
        matches(
          RegExp(
            r'^google_fonts (Lobster|NotoSansJP)-Regular\.ttf is not cached '
            'and could not be downloaded',
          ),
        ),
      );
      expect(shot.at, 'lib/preview/google_fonts_preview.dart:8');
    },
  );

  test('shadowing, throwing, resolved, unpainted, and crashing previews '
      'are reported', () async {
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
      'lib/preview/crash_preview.dart': '''
import 'dart:io';

import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';

@Preview(name: 'Crash', size: Size(80, 40))
Widget crash() => exit(3);
''',
    });
    await shutter(root, ['shot', 'lib/preview/boom_preview.dart']);
    expect(
      RunManifest.read(lastRun(root)).shots.single.error,
      contains('boom'),
    );

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

    final shadow = await shutter(root, [
      'shot',
      'lib/preview/shadow_preview.dart',
    ]);
    expect(shadow.exitCode, 0, reason: shadow.stdout + shadow.stderr);

    await shutter(root, ['shot', 'lib/preview/crash_preview.dart']);
    final crash = RunManifest.read(lastRun(root)).shots.single;
    expect(crash.status, ShotStatus.error);
    expect(crash.error, startsWith('no result'));

    writeFiles(root, {
      'lib/preview/shell.dart': '''
import 'package:flutter/widgets.dart';

Widget shell(Widget child) => const SizedBox();
''',
    });
    await shutter(root, ['shot', 'lib/preview/settings_page_preview.dart']);
    expect(
      RunManifest.read(lastRun(root)).shots.single.error,
      startsWith('nothing was painted'),
    );
  });
}

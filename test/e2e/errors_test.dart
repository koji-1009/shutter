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

  test('a preview that ends the test process has no result', () async {
    final root = await exampleCopy();
    writeFiles(root, {
      'lib/preview/crash_preview.dart': '''
import 'dart:io';

import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';

@Preview(name: 'Crash', size: Size(80, 40))
Widget crash() => exit(3);
''',
    });
    await shutter(root, ['shot', 'lib/preview/crash_preview.dart']);
    final crash = RunManifest.read(lastRun(root)).shots.single;
    expect(crash.status, ShotStatus.error);
    expect(crash.error, startsWith('no result'));
  });

  test('a shell that drops its child paints nothing', () async {
    final root = await exampleCopy();
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

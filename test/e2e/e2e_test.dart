@Tags(['e2e'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shutter/src/cli/context.dart';
import 'package:shutter/src/engine/flutter_test_engine.dart';
import 'package:shutter/src/project/flutter_sdk.dart';
import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers.dart';

/// Copies `example/` (sources only) into a temporary project and
/// resolves its dependencies.
Future<String> exampleCopy() async {
  final root = tempDir();
  for (final entity in Directory('example').listSync(recursive: true)) {
    final rel = p.relative(entity.path, from: 'example');
    if (entity is! File ||
        rel.startsWith('.dart_tool') ||
        rel.startsWith('.shutter') ||
        rel.startsWith('build')) {
      continue;
    }
    File(p.join(root, rel))
      ..createSync(recursive: true)
      ..writeAsBytesSync(entity.readAsBytesSync());
  }
  final pubGet = await Process.run(flutter, [
    'pub',
    'get',
  ], workingDirectory: root);
  expect(pubGet.exitCode, 0, reason: '${pubGet.stdout}${pubGet.stderr}');
  return root;
}

final String flutter = FlutterSdk.require(environment: Platform.environment)
    .executable();

Future<CliResult> shutter(String root, List<String> args) =>
    runCli(args, ShutterContext(workingDirectory: root));

/// Every preview file of `example/`.
const examplePreviews = [
  'lib/preview/button_preview.dart',
  'lib/preview/google_fonts_preview.dart',
  'lib/preview/inbox_preview.dart',
  'lib/preview/media_preview.dart',
  'lib/preview/misc_preview.dart',
  'lib/preview/settings_page_preview.dart',
];

String lastRun(String root) => (Directory(
  p.join(root, '.shutter', 'runs'),
).listSync().map((d) => d.path).toList()..sort()).last;

void main() {
  test('shot → edit → shot → diff on the example app', () async {
    final root = await exampleCopy();

    final before = await shutter(root, ['shot', ...examplePreviews]);
    expect(before.exitCode, 2, reason: before.stdout + before.stderr);
    // The run directory the agent is told to pass to diff.
    final beforeRun = (loadYaml(before.stdout) as YamlMap)['run'] as String;
    final manifest = RunManifest.read(beforeRun);
    expect(manifest.shots, hasLength(20));
    expect(
      manifest.shots
          .where((s) => s.status == ShotStatus.error)
          .map((s) => s.name),
      unorderedEquals(['TagRow / overflow', 'Avatar / network image']),
    );
    final overflow = manifest.shots.singleWhere(
      (s) => s.name == 'TagRow / overflow',
    );
    expect(overflow.error, startsWith('A RenderFlex overflowed by'));
    expect(overflow.at, 'lib/ui/tag_row.dart:11:12');
    expect(overflow.png, isNotNull);
    final button = manifest.shots.singleWhere(
      (s) => s.name == 'PrimaryButton / short',
    );
    expect(button.size!.$2, 56);
    final bytes = File(p.join(beforeRun, button.png)).readAsBytesSync();
    // PNG IHDR: width and height at bytes 16..23, rendered at 2x.
    final header = ByteData.sublistView(bytes, 16, 24);
    expect(header.getUint32(0), closeTo(button.size!.$1 * 2, 1));
    expect(header.getUint32(4), 112);
    final network = manifest.shots.singleWhere(
      (s) => s.name == 'Avatar / network image',
    );
    expect(network.error, startsWith('HTTP request failed, statusCode: 400'));
    expect(network.at, 'lib/preview/media_preview.dart:18:26');
    final greeting = manifest.shots.singleWhere(
      (s) => s.name == 'GreetingCard / google_fonts',
    );
    expect(greeting.status, ShotStatus.ok);
    expect(
      Directory(p.join(root, '.shutter', 'fonts', 'google_fonts'))
          .listSync()
          .where((f) => f.path.endsWith('.ttf')),
      hasLength(2),
    );
    final dark = manifest.shots.singleWhere(
      (s) => s.name == 'Inbox / empty / dark',
    );
    expect(dark.brightness, 'dark');
    expect(Directory(p.join(beforeRun, '.results')).existsSync(), isFalse);
    expect(
      Directory(p.join(root, '.shutter', 'test')).listSync(),
      isEmpty,
      reason: 'the generated test is deleted after the shot',
    );

    final button2 = File(p.join(root, 'lib', 'ui', 'button.dart'));
    button2.writeAsStringSync(
      button2.readAsStringSync().replaceFirst(
        'horizontal: 24, vertical: 16',
        'horizontal: 32, vertical: 12',
      ),
    );
    final after = await shutter(root, ['shot', ...examplePreviews]);
    expect(after.exitCode, 2);
    final afterRun = (loadYaml(after.stdout) as YamlMap)['run'] as String;

    final diff = await shutter(root, ['diff', beforeRun, afterRun, '--images']);
    expect(diff.exitCode, 1);
    final report = loadYaml(diff.stdout) as YamlMap;
    final statuses = {
      for (final e in (report['entries'] as YamlList).cast<YamlMap>())
        e['name']: e['status'],
    };
    // The same overflow before and after is no change.
    expect(statuses['TagRow / overflow'], 'unchanged');
    expect(statuses['Avatar / network image'], 'unchanged');
    for (final name in [
      'LoginForm',
      'PrimaryButton / short',
      'PrimaryButton / long',
      'PrimaryButton / Japanese',
    ]) {
      expect(statuses[name], 'changed', reason: name);
    }
    expect(statuses.values.where((s) => s == 'unchanged'), hasLength(16));
    final short = (report['entries'] as YamlList).cast<YamlMap>().singleWhere(
      (e) => e['name'] == 'PrimaryButton / short',
    );
    expect(File(short['diff'] as String).existsSync(), isTrue);
    expect(File(short['before'] as String).existsSync(), isTrue);
  });

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

  test('--widget shoots one widget without touching lib/; a broken one '
      'is an error shot', () async {
    final root = await exampleCopy();
    List<String> libFiles() => [
      for (final f in Directory(p.join(root, 'lib')).listSync(recursive: true))
        p.relative(f.path, from: root),
    ]..sort();
    final before = libFiles();
    final result = await shutter(root, [
      'shot',
      '--widget',
      'const PrimaryButton(label: "Widget")',
      '--import',
      'lib/ui/button.dart',
      '--size',
      '200x56',
    ]);
    expect(result.exitCode, 0, reason: result.stdout + result.stderr);
    final shot = RunManifest.read(lastRun(root)).shots.single;
    expect(shot.name, 'const PrimaryButton(label: "Widget")');
    expect((shot.status, shot.file), (ShotStatus.ok, null));
    expect(shot.size, (200.0, 56.0));
    expect(libFiles(), before);

    // Without --size the widget is shot at its own size.
    final natural = await shutter(root, [
      'shot',
      '--widget',
      'const PrimaryButton(label: "Widget")',
      '--import',
      'lib/ui/button.dart',
    ]);
    expect(natural.exitCode, 0, reason: natural.stdout + natural.stderr);
    final own = RunManifest.read(lastRun(root)).shots.single.size!;
    expect(own.$1, lessThan(200));
    expect(own.$2, 52);

    final broken = await shutter(root, ['shot', '--widget', 'Missing()']);
    expect(broken.exitCode, 2, reason: broken.stdout + broken.stderr);
    final brokenRun = (loadYaml(broken.stdout) as YamlMap)['run'] as String;
    final error = RunManifest.read(brokenRun).shots.single;
    expect(error.name, 'Missing()');
    expect(error.error, "Method not found: 'Missing'.");

    // The same compile error in another run is no change.
    final again = await shutter(root, ['shot', '--widget', 'Missing()']);
    final againRun = (loadYaml(again.stdout) as YamlMap)['run'] as String;
    final diff = await shutter(root, ['diff', brokenRun, againRun]);
    expect(diff.exitCode, 0, reason: diff.stdout + diff.stderr);
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

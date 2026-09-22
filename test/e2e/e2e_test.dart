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
  p.join(root, '.dart_tool', 'shutter', 'runs'),
).listSync().map((d) => d.path).toList()..sort()).last;

/// Shoots [args] in [root]: the run directory and its shots by name.
Future<(String, Map<String, Shot>)> shootIn(
  String root,
  List<String> args,
) async {
  final result = await shutter(root, ['shot', ...args]);
  final run = (loadYaml(result.stdout) as YamlMap)['run'] as String;
  return (run, {for (final s in RunManifest.read(run).shots) s.name: s});
}

/// A button that pushes a page.
const routePreview = '''
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

@Preview(name: 'Route', size: Size(200, 100))
Widget route() => Builder(
  builder: (context) => ElevatedButton(
    onPressed: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Next page')),
      ),
    ),
    child: const Text('Go'),
  ),
);
''';

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
      Directory(p.join(root, '.dart_tool', 'shutter', 'fonts', 'google_fonts'))
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
      Directory(p.join(root, '.dart_tool', 'shutter', 'test')).listSync(),
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

  test(
    'actions change the shot; a target they cannot reach is an error',
    () async {
      final root = await exampleCopy();
      Future<(String, Map<String, Shot>)> shoot(List<String> args) =>
          shootIn(root, args);
      writeFiles(root, {
        'lib/preview/route_preview.dart': routePreview,
        'lib/preview/button_state_preview.dart': '''
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

@Preview(name: 'State / button', size: Size(200, 80))
Widget button() => Center(
  child: ElevatedButton(onPressed: () {}, child: const Text('Save')),
);

@Preview(name: 'State / two buttons', size: Size(200, 80))
Widget twoButtons() => Row(
  children: [
    TextButton(onPressed: () {}, child: const Text('Save')),
    TextButton(onPressed: () {}, child: const Text('Save')),
  ],
);
''',
      });
      const buttons = 'lib/preview/button_state_preview.dart';
      final (plain, _) = await shoot([buttons]);
      for (final action in [
        ['--press', 'text:Save'],
        ['--hover', 'type:ElevatedButton'],
        ['--focus', 'type:ElevatedButton'],
      ]) {
        final (run, shots) = await shoot([buttons, ...action]);
        final button = shots['State / button']!;
        expect(button.status, ShotStatus.ok, reason: '$action ${button.error}');
        expect(button.size, (200.0, 80.0));
        final two = shots['State / two buttons']!;
        expect(two.png, isNull);
        expect(two.at, startsWith('lib/preview/button_state_preview.dart:'));
        final diff = await shutter(root, ['diff', plain, run]);
        final report = loadYaml(diff.stdout) as YamlMap;
        expect(report['actions'], {
          'before': <Object?>[],
          'after': ['${action[0].substring(2)} ${action[1]}'],
        });
        final entry = (report['entries'] as YamlList)
            .cast<YamlMap>()
            .singleWhere((e) => e['name'] == 'State / button');
        expect(entry['status'], 'changed', reason: '$action');
      }
      final (_, missed) = await shoot([buttons, '--tap', 'text:Cancel']);
      expect(
        missed['State / button']!.error,
        'tap text:Cancel: no widget matches',
      );
      expect(
        missed['State / two buttons']!.error,
        'tap text:Cancel: no widget matches',
      );
      final (_, twice) = await shoot([buttons, '--press', 'text:Save']);
      expect(
        twice['State / two buttons']!.error,
        'press text:Save: 2 widgets match; name one',
      );
      writeFiles(root, {
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
        startsWith(
          'tap text:Hidden: a pointer at its centre does not reach it',
        ),
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

      // Taps run in order: the second finds what the first expanded.
      writeFiles(root, {
        'lib/preview/tile_state_preview.dart': '''
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

@Preview(name: 'State / tile', size: Size(240, 200))
Widget tile() => const Material(
  child: ExpansionTile(title: Text('More'), children: [_Agree()]),
);

class _Agree extends StatefulWidget {
  const _Agree();

  @override
  State<_Agree> createState() => _AgreeState();
}

class _AgreeState extends State<_Agree> {
  bool agreed = false;

  @override
  Widget build(BuildContext context) => Checkbox(
    value: agreed,
    onChanged: (value) => setState(() => agreed = value!),
  );
}
''',
      });
      const tile = 'lib/preview/tile_state_preview.dart';
      final (expanded, _) = await shoot([tile, '--tap', 'text:More']);
      final (checked, checkedShots) = await shoot([
        tile,
        '--tap',
        'text:More',
        '--tap',
        'type:Checkbox',
      ]);
      final agreed = checkedShots['State / tile']!;
      expect(agreed.status, ShotStatus.ok, reason: agreed.error);
      expect((await shutter(root, ['diff', expanded, checked])).exitCode, 1);
      final (_, reversed) = await shoot([
        tile,
        '--tap',
        'type:Checkbox',
        '--tap',
        'text:More',
      ]);
      expect(
        reversed['State / tile']!.error,
        'tap type:Checkbox: no widget matches',
      );
    },
  );

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

  test('--enter types into a field, in order with the taps', () async {
    final root = await exampleCopy();
    Future<(String, Map<String, Shot>)> shoot(List<String> args) =>
        shootIn(root, args);
    writeFiles(root, {
      'lib/preview/form_preview.dart': '''
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

@Preview(name: 'Form', size: Size(240, 160))
Widget form() => const Material(child: _Greeting());

class _Greeting extends StatefulWidget {
  const _Greeting();

  @override
  State<_Greeting> createState() => _GreetingState();
}

class _GreetingState extends State<_Greeting> {
  final controller = TextEditingController();
  String? shown;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextField(key: const ValueKey('name'), controller: controller),
      TextButton(
        onPressed: () => setState(
          () => shown = controller.text.isEmpty
              ? 'Name is empty'
              : 'Hello, \${controller.text}',
        ),
        child: const Text('Submit'),
      ),
      if (shown case final shown?) Text(shown),
    ],
  );
}
''',
    });
    const form = 'lib/preview/form_preview.dart';
    final (blank, _) = await shoot([form]);
    final (typed, typedShots) = await shoot([form, '--enter', 'key:name=Koji']);
    expect(typedShots['Form']!.status, ShotStatus.ok);
    expect((await shutter(root, ['diff', blank, typed])).exitCode, 1);
    final (enterFirst, _) = await shoot([
      form,
      '--enter',
      'key:name=Koji',
      '--tap',
      'text:Submit',
      '--settle',
      '700',
    ]);
    final (tapFirst, _) = await shoot([
      form,
      '--tap',
      'text:Submit',
      '--enter',
      'key:name=Koji',
      '--settle',
      '700',
    ]);
    expect((await shutter(root, ['diff', enterFirst, tapFirst])).exitCode, 1);
    final (_, noField) = await shoot([form, '--enter', 'text:Submit=x']);
    expect(
      noField['Form']!.error,
      'enter text:Submit=x: the widget holds no text field',
    );
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

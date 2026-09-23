import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shutter/src/engine/interaction.dart';
import 'package:shutter/src/engine/widget_shot.dart';
import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers.dart';
import 'fakes.dart';

void main() {
  test('writes the run manifest in source order; exit 0 when all ok', () async {
    final root = createProject();
    final engine = FakeEngine(const [
      Shot(
        id: 'b.0',
        status: ShotStatus.ok,
        name: 'b',
        file: 'lib/b.dart',
        png: 'b.0.png',
      ),
      Shot(
        id: 'a.0',
        status: ShotStatus.ok,
        name: 'a',
        file: 'lib/a.dart',
        png: 'a.0.png',
      ),
    ]);
    final result = await runCli([
      'shot',
      '--settle',
      '120',
      '--widget',
      'A()',
    ], fakeContext(root, engine: engine));
    expect(result.exitCode, 0, reason: result.stderr);
    final runDir = p.join(
      root,
      '.dart_tool',
      'shutter',
      'runs',
      '20260918T101530Z',
    );
    final manifest = RunManifest.read(runDir);
    expect(manifest.run, '20260918T101530Z');
    expect(manifest.shots.map((s) => s.id), ['a.0', 'b.0']);
    expect(engine.requests.single.settleMs, 120);
    expect(
      File(p.join(root, '.gitignore')).existsSync(),
      isFalse,
      reason: 'shutter writes only under .dart_tool/',
    );
    expect(result.stdout, startsWith('# shutter ai-report v1\nrun: $runDir\n'));
  });

  test('exit 2 when a shot errored; --settle defaults to 300', () async {
    final root = createProject();
    final engine = FakeEngine(const [
      Shot(id: 'a.0', status: ShotStatus.error, name: 'a', error: 'boom'),
    ]);
    final result = await runCli([
      'shot',
      '--widget',
      'A()',
    ], fakeContext(root, engine: engine));
    expect(result.exitCode, 2);
    expect(engine.requests.single.settleMs, 300);
  });

  test('shoots only the named preview files, relative to the working '
      'directory', () async {
    const preview =
        "import 'package:flutter/widget_previews.dart';\n"
        "import 'package:flutter/widgets.dart';\n"
        "@Preview()\nWidget a() => const Text('');";
    final root = createProject(
      resolvable: true,
      files: {'lib/preview/a.dart': preview, 'lib/preview/b.dart': preview},
    );
    final engine = FakeEngine(const []);
    final result = await runCli([
      'shot',
      'preview/a.dart',
    ], fakeContext(p.join(root, 'lib'), engine: engine));
    expect(result.exitCode, 0, reason: result.stderr);
    final request = engine.requests.single;
    expect(request.libraries.single.file, 'lib/preview/a.dart');
    expect(request.widget, isNull);
  });

  test('--widget hands the widget to the engine without scanning or '
      'writing into lib/', () async {
    // A real preview under lib/, which a scan would find.
    final root = createProject(
      resolvable: true,
      files: {
        'lib/ui/button.dart': '',
        'lib/preview/a.dart':
            "import 'package:flutter/widget_previews.dart';\n"
            "import 'package:flutter/widgets.dart';\n"
            "@Preview()\nWidget a() => const Text('');",
      },
    );
    final engine = FakeEngine(const []);
    final result = await runCli([
      'shot',
      '--widget',
      'PrimaryButton(label: "OK")',
      '--import',
      'lib/ui/button.dart',
    ], fakeContext(root, engine: engine));
    expect(result.exitCode, 0, reason: result.stderr);
    final request = engine.requests.single;
    expect(request.libraries, isEmpty);
    final widget = request.widget!;
    expect(widget.source, 'PrimaryButton(label: "OK")');
    expect(widget.imports, [
      'package:flutter/widgets.dart',
      'package:app/ui/button.dart',
    ]);
    expect(widget.size, isNull);
    expect(
      Directory(p.join(root, 'lib'))
          .listSync(recursive: true)
          .map((e) => p.relative(e.path, from: root)),
      unorderedEquals([
        'lib/ui',
        'lib/ui/button.dart',
        'lib/preview',
        'lib/preview/a.dart',
      ]),
    );
  });

  test('--size sets the size; --import is relative to the working directory '
      'so the id does not depend on it', () async {
    final root = createProject(files: {'lib/ui/b.dart': ''});
    Future<WidgetShot> widgetFrom(String dir, String import) async {
      final engine = FakeEngine(const []);
      final result = await runCli([
        'shot',
        '--widget',
        'B()',
        '--import',
        import,
        '--size',
        '200x56.5',
      ], fakeContext(dir, engine: engine));
      expect(result.exitCode, 0, reason: result.stderr);
      return engine.requests.single.widget!;
    }

    final fromRoot = await widgetFrom(root, 'lib/ui/b.dart');
    final fromLib = await widgetFrom(p.join(root, 'lib'), 'ui/b.dart');
    expect(fromRoot.size, (200.0, 56.5));
    expect(fromLib.staticId, fromRoot.staticId);
  });

  test('--import is repeatable; package: URIs pass through', () async {
    final root = createProject(files: {'lib/ui/a.dart': ''});
    final engine = FakeEngine(const []);
    await runCli([
      'shot',
      '--widget',
      'A(Text("x"))',
      '--import',
      'lib/ui/a.dart',
      '--import',
      'package:flutter/material.dart',
    ], fakeContext(root, engine: engine));
    expect(engine.requests.single.widget!.imports, [
      'package:flutter/widgets.dart',
      'package:app/ui/a.dart',
      'package:flutter/material.dart',
    ]);
  });

  test('the shell: --shell from anywhere, else the preview dir, recorded '
      'with its sha256 in the manifest', () async {
    final root = createProject(
      files: {
        'lib/preview/shell.dart': '// project',
        '.dart_tool/shutter/shell.dart': '// cached',
      },
    );
    Future<(String?, ShellFile?)> shoot(List<String> args) async {
      final engine = FakeEngine(const []);
      final result = await runCli([
        'shot',
        '--widget',
        'A()',
        ...args,
      ], fakeContext(root, engine: engine));
      expect(result.exitCode, 0, reason: result.stderr);
      final run = (loadYaml(result.stdout) as YamlMap)['run'] as String;
      return (engine.requests.single.shell, RunManifest.read(run).shell);
    }

    final cached = p.join(root, '.dart_tool', 'shutter', 'shell.dart');
    expect(await shoot(['--shell', '.dart_tool/shutter/shell.dart']), (
      cached,
      (
        path: '.dart_tool/shutter/shell.dart',
        sha256: sha256.convert(utf8.encode('// cached')).toString(),
      ),
    ));
    expect(await shoot([]), (
      p.join(root, 'lib', 'preview', 'shell.dart'),
      (
        path: 'lib/preview/shell.dart',
        sha256: sha256.convert(utf8.encode('// project')).toString(),
      ),
    ));
    final outside = p.join(tempDir(), 'shell.dart');
    File(outside).writeAsStringSync('');
    expect((await shoot(['--shell', outside])).$2?.path, outside);

    File(p.join(root, 'lib', 'preview', 'shell.dart')).deleteSync();
    expect(await shoot([]), (null, null));

    final missing = await runCli([
      'shot',
      '--widget',
      'A()',
      '--shell',
      'nope.dart',
    ], fakeContext(root));
    expect(missing.exitCode, 66);
    expect(missing.stderr, contains('--shell nope.dart does not exist.'));
  });

  test('actions: every --tap in order, then the held one; recorded in the '
      'manifest and the report with the capture', () async {
    final root = createProject();
    final engine = FakeEngine(const []);
    final result = await runCli([
      'shot',
      '--widget',
      'A()',
      '--tap',
      'text:Open, then close',
      '--press',
      'key:save',
      '--enter=key:name=Koji=K',
      '--tap',
      'type:DropdownButton<String>',
      '--enter',
      'label:Email=',
      '--capture',
      'screen',
      '--viewport',
      '390x844',
    ], fakeContext(root, engine: engine));
    expect(result.exitCode, 0, reason: result.stderr);
    final request = engine.requests.single;
    expect(
      [
        for (final action in request.actions)
          (action.kind, action.by, action.value, action.text),
      ],
      [
        (ActionKind.tap, TargetKind.text, 'Open, then close', null),
        (ActionKind.enter, TargetKind.key, 'name', 'Koji=K'),
        (ActionKind.tap, TargetKind.type, 'DropdownButton<String>', null),
        (ActionKind.enter, TargetKind.label, 'Email', ''),
        (ActionKind.press, TargetKind.key, 'save', null),
      ],
    );
    expect((request.screen, request.viewport), (true, (390.0, 844.0)));
    final report = loadYaml(result.stdout) as YamlMap;
    const labels = [
      'tap text:Open, then close',
      'enter key:name=Koji=K',
      'tap type:DropdownButton<String>',
      'enter label:Email=',
      'press key:save',
    ];
    expect(report['actions'], labels);
    expect(report['capture'], 'screen');
    expect(report['viewport'], [390, 844]);
    final manifest = RunManifest.read(report['run'] as String);
    expect(manifest.actions, labels);
    expect((manifest.screen, manifest.viewport), (true, (390.0, 844.0)));

    for (final (flag, kind) in [
      ('--hover', ActionKind.hover),
      ('--focus', ActionKind.focus),
    ]) {
      final held = FakeEngine(const []);
      await runCli([
        'shot',
        '--widget',
        'A()',
        flag,
        'type:TextField',
      ], fakeContext(root, engine: held));
      final request = held.requests.single;
      expect(request.actions.single.kind, kind);
      expect((request.screen, request.viewport), (false, null));
    }
  });

  test('a named file without previews is missing input', () async {
    final root = createProject(
      resolvable: true,
      files: {'lib/ui/plain.dart': 'int x() => 0;'},
    );
    final result = await runCli([
      'shot',
      'lib/ui/plain.dart',
    ], fakeContext(root));
    expect(result.exitCode, 66);
    expect(result.stderr, contains('lib/ui/plain.dart has no @Preview.'));
  });

  test('usage and project errors', () async {
    final root = createProject(files: {'outside.dart': ''});
    Future<CliResult> run(List<String> args, [String? dir]) =>
        runCli(['shot', ...args], fakeContext(dir ?? root));
    for (final args in [
      ['--import', 'x'],
      ['--size', '1x1'],
    ]) {
      final bad = await run(args);
      expect(bad.exitCode, 64, reason: '$args');
      expect(bad.stderr, contains('--import and --size need --widget.'));
      // Followed by the command's usage, as for a parser error.
      expect(bad.stderr, contains('Usage: shutter shot'));
    }
    for (final args in [
      <String>[],
      ['lib/a.dart', '--widget', 'x'],
    ]) {
      final bad = await run(args);
      expect(bad.exitCode, 64, reason: '$args');
      expect(bad.stderr, contains('Name the preview files to shoot'));
    }
    expect((await run(['outside.dart'])).exitCode, 64);
    expect((await run(['lib/nope.dart'])).exitCode, 66);
    for (final size in ['1', '0x1', '1x-1', 'axb', '1x2x3', 'Infinityx1']) {
      final bad = await run(['--widget', 'x', '--size', size]);
      expect(bad.exitCode, 64, reason: size);
      expect(bad.stderr, contains('--size must be'));
    }
    for (final settle in ['soon', '-1']) {
      final bad = await run(['--widget', 'x', '--settle', settle]);
      expect(bad.exitCode, 64, reason: settle);
      expect(bad.stderr, contains('--settle must be a whole number'));
    }
    for (final (option, target) in [
      ('--tap', 'Save'),
      ('--tap', 'name:Save'),
      ('--tap', 'text:'),
      ('--enter', 'name=Koji'),
    ]) {
      final bad = await run(['--widget', 'x', option, target]);
      expect(bad.exitCode, 64, reason: target);
      expect(
        bad.stderr,
        contains(
          '$option must name its widget by key:<key>, text:<text>, '
          'label:<label>, or type:<Widget>',
        ),
      );
    }
    final noText = await run(['--widget', 'x', '--enter', 'key:name']);
    expect(noText.exitCode, 64);
    expect(noText.stderr, contains('--enter must be <target>=<text>'));
    for (final second in ['--focus', '--press']) {
      final held = await run([
        '--widget',
        'x',
        '--press',
        'key:a',
        second,
        'key:b',
      ]);
      expect(held.exitCode, 64, reason: second);
      expect(held.stderr, contains('at most one of --press, --hover'));
    }
    final viewport = await run(['--widget', 'x', '--viewport', '390x844']);
    expect(viewport.exitCode, 64);
    expect(viewport.stderr, contains('--viewport needs --capture screen.'));
    final badViewport = await run([
      '--widget',
      'x',
      '--capture',
      'screen',
      '--viewport',
      '390',
    ]);
    expect(badViewport.exitCode, 64);
    expect(badViewport.stderr, contains('--viewport must be <width>x<height>'));
    final outside = await run(['--widget', 'x', '--import', 'outside.dart']);
    expect(outside.exitCode, 64);
    expect(outside.stderr, contains('--import must be under lib/'));
    expect(
      (await run(['--widget', 'x', '--import', 'nope.dart'])).exitCode,
      66,
    );
    expect(
      Directory(p.join(root, '.dart_tool', 'shutter')).existsSync(),
      isFalse,
      reason: 'a shot that fails its checks leaves the project alone',
    );
    final noTest = await run(['x.dart'], createProject(flutterTest: false));
    expect(noTest.exitCode, 78);
    expect(noTest.stderr, contains('flutter_test is not in dev_dependencies'));
  });
}

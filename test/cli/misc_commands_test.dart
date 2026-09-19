import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shutter/src/cli/agent_text.dart';
import 'package:shutter/src/cli/context.dart';
import 'package:shutter/src/cli/init_command.dart';
import 'package:shutter/src/cli/manual_text.dart';
import 'package:shutter/src/cli/runner.dart';
import 'package:shutter/src/engine/flutter_test_engine.dart';
import 'package:shutter/src/project/flutter_sdk.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'fakes.dart';

void main() {
  group('doctor', () {
    test('all checks pass', () async {
      final root = createProject(files: {'lib/preview/shell.dart': ''});
      final result = await runCli(['doctor'], fakeContext(root));
      expect(result.exitCode, 0);
      expect(result.stdout, contains('[OK]   Flutter 3.47.4 at '));
      expect(result.stdout, contains('[OK]   font cache: '));
      expect(result.stdout, contains('[OK]   project app at $root'));
      expect(result.stdout, contains('[OK]   shell lib/preview/shell.dart'));
    });

    test('warnings keep exit 0', () async {
      final root = createProject();
      final result = await runCli([
        'doctor',
      ], fakeContext(root, sdk: createSdk(version: null, fonts: false)));
      expect(result.exitCode, 0);
      expect(result.stdout, contains('[WARN] Flutter SDK at '));
      expect(result.stdout, contains('       run `flutter --version` once'));
      expect(result.stdout, contains('[WARN] font cache missing: '));
      expect(result.stdout, contains('[WARN] no shell.dart'));
      expect(result.stdout, contains('       run `shutter init`'));
    });

    test('failures exit 1', () async {
      final old = await runCli([
        'doctor',
      ], fakeContext(createProject(), sdk: createSdk(version: '3.46.0')));
      expect(old.exitCode, 1);
      expect(old.stdout, contains('shutter needs 3.47.0 or newer'));

      final missing = await runCli([
        'doctor',
      ], fakeContext(tempDir(), environment: const {}));
      expect(missing.exitCode, 1);
      expect(missing.stdout, contains('[FAIL] Flutter SDK not found'));
      expect(missing.stdout, contains('[FAIL] no pubspec.yaml found'));
    });

    test('an empty font directory is a warning', () async {
      final sdk = createSdk(fonts: false);
      Directory(p.join(sdk, 'bin', 'cache', 'artifacts', 'material_fonts'))
          .createSync(recursive: true);
      final result = await runCli([
        'doctor',
      ], fakeContext(createProject(), sdk: sdk));
      expect(result.stdout, contains('[WARN] font cache missing'));
    });
  });

  test('init writes the shell once', () async {
    final root = createProject();
    final first = await runCli(['init'], fakeContext(root));
    expect(first.exitCode, 0);
    expect(first.stdout, 'wrote    lib/preview/shell.dart\n');
    expect(
      File(p.join(root, 'lib', 'preview', 'shell.dart')).readAsStringSync(),
      shellTemplate(const {}).trimLeft(),
    );
    writeFiles(root, {'lib/preview/shell.dart': '// mine'});
    final second = await runCli(['init'], fakeContext(root));
    expect(second.exitCode, 0);
    expect(second.stdout, 'kept     lib/preview/shell.dart (already exists)\n');
    expect(
      File(p.join(root, 'lib', 'preview', 'shell.dart')).readAsStringSync(),
      '// mine',
    );
  });

  test('the shell template follows the design package the project uses', () {
    final legacy = shellTemplate(const {});
    expect(legacy, startsWith("import 'package:flutter/material.dart';"));
    expect(legacy, contains('home: Material(child: child)'));
    final material = shellTemplate(const {'material_ui', 'cupertino_ui'});
    expect(
      material,
      startsWith("import 'package:material_ui/material_ui.dart';"),
    );
    expect(material, contains('MaterialApp('));
    final cupertino = shellTemplate(const {'cupertino_ui'});
    expect(
      cupertino,
      startsWith("import 'package:cupertino_ui/cupertino_ui.dart';"),
    );
    expect(cupertino, contains('CupertinoApp('));
  });

  test('agent and manual print the shipped texts', () async {
    final root = createProject();
    expect((await runCli(['agent'], fakeContext(root))).stdout, agentText);
    expect((await runCli(['manual'], fakeContext(root))).stdout, manualText);
  });

  test('usage mentions the agent playbook', () async {
    final result = await runCli(['--help'], fakeContext(createProject()));
    expect(result.stdout, contains('AI agents: run `shutter agent` first'));
  });

  test('usage shows the positional arguments', () {
    final runner = buildCommandRunner(fakeContext(createProject()));
    expect(
      runner.commands['diff']!.usage,
      contains('shutter diff <run-a> <run-b>'),
    );
    expect(
      runner.commands['shot']!.usage,
      contains('shutter shot <preview-file>...'),
    );
  });

  test('default context reads the real process state', () async {
    final context = ShutterContext();
    expect(context.workingDirectory, Directory.current.path);
    expect(context.clock().isUtc, isFalse);
    expect(context.environment, Platform.environment);
    expect(context.engineFactory(FlutterSdk('/sdk')), isA<FlutterTestEngine>());
  });
}

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shutter/src/cli/context.dart';
import 'package:shutter/src/project/flutter_sdk.dart';
import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers.dart';

/// Copies `example/` (sources only) into a temporary project, [into]
/// when given, and resolves its dependencies.
Future<String> exampleCopy({String? into}) async {
  final root = into ?? tempDir();
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

/// Declares, in `main`, a copy of `example/` for the tests of the file
/// that only add files to it, each under names of its own; a test that
/// changes what is there takes an [exampleCopy] of its own. The copy, its
/// compiled tests, and the analysis of its previews then carry over from
/// test to test. The returned function makes the copy when a test first
/// asks for it; it is deleted after the file's last test.
Future<String> Function() sharedExample() {
  Directory? dir;
  Future<String>? copy;
  tearDownAll(() => dir?.deleteSync(recursive: true));
  return () => copy ??= exampleCopy(
    into: (dir = Directory.systemTemp.createTempSync(
      'shutter_test_',
    )).resolveSymbolicLinksSync(),
  );
}

final String flutter = FlutterSdk.require(environment: Platform.environment)
    .executable();

Future<CliResult> shutter(String root, List<String> args) =>
    runCli(args, ShutterContext(workingDirectory: root));

String lastRun(String root) => (Directory(
  p.join(root, '.dart_tool', 'shutter', 'runs'),
).listSync().map((d) => d.path).toList()..sort()).last;

/// Shoots [args] in [root]: the run directory and its shots by name.
Future<(String, Map<String, Shot>)> shootIn(
  String root,
  List<String> args,
) async {
  final result = await shutter(root, ['shot', ...args]);
  final report = loadYaml(result.stdout);
  expect(report, isA<YamlMap>(), reason: result.stdout + result.stderr);
  final run = (report as YamlMap)['run'] as String;
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

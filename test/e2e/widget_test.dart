@Tags(['e2e'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'e2e_helpers.dart';

void main() {
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
}

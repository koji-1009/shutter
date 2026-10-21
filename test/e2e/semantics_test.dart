@Tags(['e2e'])
library;

import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'e2e_helpers.dart';

void main() {
  test('semantics draws the tree at the size of the shot, and its diff '
      'shows a change the pixels do not', () async {
    final root = await exampleCopy();
    const previews = 'lib/preview/button_preview.dart';
    Future<String> run(String command, [List<String> args = const []]) async {
      final result = await shutter(root, [command, previews, ...args]);
      expect(result.exitCode, 0, reason: result.stdout + result.stderr);
      return (loadYaml(result.stdout) as YamlMap)['run'] as String;
    }

    (int, int) pngSize(String run, Shot shot) {
      final image = img.decodePng(
        File(p.join(run, shot.png!)).readAsBytesSync(),
      )!;
      return (image.width, image.height);
    }

    final paintBefore = await run('shot');
    final treeBefore = await run('semantics');
    final painted = {
      for (final s in RunManifest.read(paintBefore).shots) s.id: s,
    };
    final tree = RunManifest.read(treeBefore);
    expect(tree.setup.semantics, isTrue);
    expect(tree.shots.map((s) => s.id), unorderedEquals(painted.keys));
    for (final shot in tree.shots) {
      expect(shot.status, ShotStatus.ok, reason: shot.name);
      expect(shot.size, painted[shot.id]!.size, reason: shot.name);
      expect(
        pngSize(treeBefore, shot),
        pngSize(paintBefore, painted[shot.id]!),
        reason: shot.name,
      );
    }

    // The button leaves the semantics tree and stays on screen.
    final form = File(p.join(root, 'lib/ui/login_form.dart'));
    form.writeAsStringSync(
      form.readAsStringSync().replaceFirst(
        "const PrimaryButton(label: 'Sign in'),",
        "const ExcludeSemantics(child: PrimaryButton(label: 'Sign in')),",
      ),
    );
    final paintAfter = await run('shot');
    final treeAfter = await run('semantics');
    final paintDiff = await shutter(root, ['diff', paintBefore, paintAfter]);
    expect(paintDiff.exitCode, 0, reason: paintDiff.stdout + paintDiff.stderr);
    final treeDiff = await shutter(root, ['diff', treeBefore, treeAfter]);
    expect(treeDiff.exitCode, 1, reason: treeDiff.stdout + treeDiff.stderr);
    final report = loadYaml(treeDiff.stdout) as YamlMap;
    expect(report['summary'], {
      'changed': 1,
      'added': 0,
      'removed': 0,
      'unchanged': 3,
    });
    expect(
      ((report['entries'] as YamlList).first as YamlMap)['name'],
      'LoginForm',
    );

    // The whole screen, at the scale of the preview.
    final result = await shutter(root, [
      'semantics',
      '--widget',
      'Text("Sign in")',
      '--capture',
      'screen',
      '--viewport',
      '400x300',
    ]);
    expect(result.exitCode, 0, reason: result.stdout + result.stderr);
    final screen = (loadYaml(result.stdout) as YamlMap)['run'] as String;
    final shot = RunManifest.read(screen).shots.single;
    expect(shot.status, ShotStatus.ok);
    expect(pngSize(screen, shot), (800, 600));
  });
}

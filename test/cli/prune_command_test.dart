import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shutter/src/project/project.dart';
import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers.dart';
import 'fakes.dart';

void main() {
  test('prune --keep prints the runs it removed and kept', () async {
    final root = createProject();
    final runs = Project.load(root).runsDir;
    for (final id in ['20260918T101530Z', '20260918T101531Z']) {
      final dir = p.join(runs, id);
      Directory(dir).createSync(recursive: true);
      RunManifest(run: id, shots: const []).write(dir);
    }
    final result = await runCli(['prune', '--keep', '1'], fakeContext(root));
    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.stdout, startsWith('# shutter ai-report v1\n'));
    expect(loadYaml(result.stdout), {
      'removed': [p.join(runs, '20260918T101530Z')],
      'kept': [p.join(runs, '20260918T101531Z')],
    });
    final none = await runCli(['prune', '--keep', '0'], fakeContext(root));
    expect(loadYaml(none.stdout), {
      'removed': [p.join(runs, '20260918T101531Z')],
      'kept': <Object?>[],
    });
    final empty = await runCli(['prune', '--keep', '0'], fakeContext(root));
    expect(empty.stdout, '# shutter ai-report v1\nremoved: []\nkept: []\n');
  });

  test('usage errors', () async {
    final root = createProject();
    Future<CliResult> run(List<String> args) =>
        runCli(['prune', ...args], fakeContext(root));
    final missing = await run([]);
    expect(missing.exitCode, 64);
    expect(missing.stderr, contains('Give --keep <n>, the runs to keep.'));
    for (final keep in ['all', '-1']) {
      final bad = await run(['--keep', keep]);
      expect(bad.exitCode, 64, reason: keep);
      expect(bad.stderr, contains('--keep must be a whole number'));
    }
    final extra = await run(['--keep', '1', 'latest']);
    expect(extra.exitCode, 64);
    expect(extra.stderr, contains('prune takes no arguments'));
    expect(extra.stderr, contains('Usage: shutter prune --keep <n>'));
  });
}

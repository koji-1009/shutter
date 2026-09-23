@Tags(['e2e'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'e2e_helpers.dart';

/// Every preview file of `example/`.
const examplePreviews = [
  'lib/preview/button_preview.dart',
  'lib/preview/google_fonts_preview.dart',
  'lib/preview/inbox_preview.dart',
  'lib/preview/media_preview.dart',
  'lib/preview/misc_preview.dart',
  'lib/preview/settings_page_preview.dart',
];

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
}

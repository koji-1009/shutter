import 'dart:convert';

import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  const full = Shot(
    id: 'a.0',
    status: ShotStatus.error,
    name: 'A',
    file: 'lib/a.dart',
    line: 3,
    size: (200, 56.5),
    brightness: 'dark',
    textScaleFactor: 1.5,
    png: 'a.0.png',
    error: 'boom',
    at: 'lib/b.dart:1:2',
  );

  test('Shot JSON round trip, integral sizes as ints', () {
    final json = full.toJson();
    // `200 == 200.0` in Dart, so compare the encoded text.
    expect(jsonEncode(json['size']), '[200,56.5]');
    expect(jsonEncode(Shot.fromJson(json).toJson()), jsonEncode(json));
    const bare = Shot(id: 'b.0', status: ShotStatus.ok, name: 'b');
    expect(bare.toJson(), {'id': 'b.0', 'status': 'ok', 'name': 'b'});
    final back = Shot.fromJson(bare.toJson());
    expect(back.size, isNull);
    expect(back.location, isNull);
  });

  test('withError points at the preview and keeps everything else', () {
    final e = full.withError('font missing');
    expect(e.toJson(), {
      ...full.toJson(),
      'error': 'font missing',
      'at': 'lib/a.dart:3',
    });
  });

  test('RunManifest write / read round trip, error count, exit code', () {
    final dir = tempDir();
    const manifest = RunManifest(
      run: '20260918T101530Z',
      shots: [
        full,
        Shot(id: 'b.0', status: ShotStatus.ok, name: 'b'),
      ],
    );
    manifest.write(dir);
    final back = RunManifest.read(dir);
    expect(jsonEncode(back.toJson()), jsonEncode(manifest.toJson()));
    expect(back.toJson().keys, ['run', 'shots']);
    expect(back.exitCode, 2);
    expect(const RunManifest(run: 'r', shots: []).exitCode, 0);
  });

  test('the shell file round-trips; the default shell writes none', () {
    final dir = tempDir();
    const RunManifest(
      run: 'r',
      shots: [],
      shell: (path: '.dart_tool/shutter/shell.dart', sha256: 'ab12'),
    ).write(dir);
    final back = RunManifest.read(dir);
    expect(back.shell, (path: '.dart_tool/shutter/shell.dart', sha256: 'ab12'));
    expect(back.toJson().keys, ['run', 'shell', 'shots']);
    expect(RunManifest.fromJson(const {'run': 'r', 'shots': []}).shell, isNull);
  });

  test('the actions and the capture round-trip; a plain run writes none', () {
    final dir = tempDir();
    const RunManifest(
      run: 'r',
      shots: [],
      setup: (
        actions: ['tap text:Open', 'press key:save'],
        screen: true,
        viewport: (390, 844.5),
      ),
    ).write(dir);
    final back = RunManifest.read(dir);
    final setup = back.setup;
    expect(setup.actions, ['tap text:Open', 'press key:save']);
    expect((setup.screen, setup.viewport), (true, (390.0, 844.5)));
    expect(back.toJson().keys, [
      'run',
      'actions',
      'capture',
      'viewport',
      'shots',
    ]);
    expect(jsonEncode(back.toJson()['viewport']), '[390,844.5]');
    final plain = RunManifest.fromJson(const {'run': 'r', 'shots': []});
    expect(plain.toJson().keys, ['run', 'shots']);
    expect(plain.setup.actions, isEmpty);
    expect((plain.setup.screen, plain.setup.viewport), (false, null));
  });
}

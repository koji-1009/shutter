import 'package:shutter/src/reporters/shot_reporter.dart';
import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers.dart';

const manifest = RunManifest(
  run: '20260918T101530Z',
  shots: [
    Shot(
      id: 'a.0',
      status: ShotStatus.ok,
      name: 'A',
      file: 'lib/preview/a.dart',
      line: 8,
      size: (200, 56),
      brightness: 'dark',
      textScaleFactor: 1.5,
      png: 'a.0.png',
    ),
    Shot(
      id: 'b.0',
      status: ShotStatus.error,
      name: 'b',
      file: 'lib/preview/b.dart',
      line: 3,
      error: 'A RenderFlex overflowed.',
      at: 'lib/ui/b.dart:4:2',
    ),
    Shot(
      id: 'c.0',
      status: ShotStatus.error,
      name: 'c.0',
      error: 'no location',
    ),
  ],
);

const dir = '/p/.dart_tool/shutter/runs/20260918T101530Z';

Future<String> render(RunManifest m) =>
    collect((sink) => reportShots(m, dir, sink));

void main() {
  test('YAML: errors first, absolute paths', () async {
    final text = await render(manifest);
    expect(text, '''
# shutter ai-report v1
run: $dir
summary: {error: 2, ok: 1}
shots:
  - id: b.0
    status: error
    name: b
    file: lib/preview/b.dart:3
    error: "A RenderFlex overflowed."
    at: lib/ui/b.dart:4:2
  - id: c.0
    status: error
    name: c.0
    error: "no location"
  - id: a.0
    status: ok
    name: A
    file: lib/preview/a.dart:8
    size: [200, 56]
    brightness: dark
    text_scale_factor: 1.5
    png: $dir/a.0.png
''');
    final yaml = loadYaml(text) as YamlMap;
    expect(yaml['summary'], {'error': 2, 'ok': 1});
    expect(
      ((yaml['shots'] as YamlList).first as YamlMap)['error'],
      'A RenderFlex overflowed.',
    );
  });

  test('no shots', () async {
    final text = await render(const RunManifest(run: 'r', shots: []));
    expect(loadYaml(text), {
      'run': dir,
      'summary': {'error': 0, 'ok': 0},
      'shots': <Object?>[],
    });
  });
}

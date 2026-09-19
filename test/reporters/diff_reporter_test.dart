import 'package:path/path.dart' as p;
import 'package:shutter/src/diff/run_diff.dart';
import 'package:shutter/src/reporters/diff_reporter.dart';
import 'package:shutter/src/run/manifest.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers.dart';

RunDiff sample() => const RunDiff(
  before: '/runs/r1',
  after: '/runs/r2',
  entries: [
    DiffEntry(
      status: DiffStatus.changed,
      shot: Shot(
        id: 'e.0',
        status: ShotStatus.error,
        name: 'Overflow',
        file: 'lib/preview/e.dart',
        line: 4,
        size: (200, 48),
        error: 'A RenderFlex overflowed.',
        at: 'lib/ui/e.dart:1:2',
      ),
    ),
    DiffEntry(
      status: DiffStatus.changed,
      shot: Shot(
        id: 'c.0',
        status: ShotStatus.ok,
        name: 'Button',
        file: 'lib/preview/c.dart',
        line: 8,
        size: (200, 56),
        brightness: 'dark',
        textScaleFactor: 1.5,
      ),
      diffRatio: 0.043217,
      beforePng: 'c.0.png',
      afterPng: 'c.0.png',
      diffPng: 'c.0.png',
    ),
    DiffEntry(
      status: DiffStatus.added,
      shot: Shot(id: 'a.0', status: ShotStatus.ok, name: 'New'),
      afterPng: 'a.0.png',
    ),
    DiffEntry(
      status: DiffStatus.unchanged,
      shot: Shot(id: 'u.0', status: ShotStatus.ok, name: 'Same'),
      diffRatio: 0,
      beforePng: 'u.0.png',
      afterPng: 'u.0.png',
    ),
  ],
);

void main() {
  test('YAML with absolute paths; the diff dir with --images', () async {
    final dir = tempDir();
    final text = await collect((sink) => reportDiff(sample(), dir, sink));
    expect(text, '''
# shutter ai-report v1
diff: $dir
before: /runs/r1
after: /runs/r2
summary: {changed: 2, added: 1, removed: 0, unchanged: 1}
entries:
  - id: e.0
    status: changed
    name: Overflow
    file: lib/preview/e.dart:4
    size: [200, 48]
    error: "A RenderFlex overflowed."
    at: lib/ui/e.dart:1:2
  - id: c.0
    status: changed
    name: Button
    file: lib/preview/c.dart:8
    size: [200, 56]
    brightness: dark
    text_scale_factor: 1.5
    diff_ratio: 0.04322
    before: /runs/r1/c.0.png
    after: /runs/r2/c.0.png
    diff: ${p.join(dir, 'c.0.png')}
  - id: a.0
    status: added
    name: New
    after: /runs/r2/a.0.png
  - id: u.0
    status: unchanged
    name: Same
    diff_ratio: 0.0
    before: /runs/r1/u.0.png
    after: /runs/r2/u.0.png
''');
    final yaml = loadYaml(text) as YamlMap;
    expect(
      ((yaml['entries'] as YamlList)[1] as YamlMap)['diff_ratio'],
      0.04322,
    );
  });

  test('without --images: no diff dir, no diff paths', () async {
    final text = await collect((sink) => reportDiff(sample(), null, sink));
    final yaml = loadYaml(text) as YamlMap;
    expect(yaml.containsKey('diff'), isFalse);
    expect(
      ((yaml['entries'] as YamlList)[1] as YamlMap).containsKey('diff'),
      isFalse,
    );
  });

  test('a change of one pixel in many keeps a nonzero ratio', () async {
    const one = RunDiff(
      before: 'a',
      after: 'b',
      entries: [
        DiffEntry(
          status: DiffStatus.changed,
          shot: Shot(id: 'x.0', status: ShotStatus.ok, name: 'x'),
          diffRatio: 1 / 480000,
        ),
      ],
    );
    final text = await collect((sink) => reportDiff(one, null, sink));
    final entry = ((loadYaml(text) as YamlMap)['entries'] as YamlList).single;
    expect((entry as YamlMap)['diff_ratio'], closeTo(1 / 480000, 1e-9));
  });
}

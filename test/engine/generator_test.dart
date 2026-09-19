import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shutter/src/engine/design.dart';
import 'package:shutter/src/engine/engine.dart';
import 'package:shutter/src/engine/generator.dart';
import 'package:shutter/src/engine/harness_text.dart';
import 'package:shutter/src/engine/widget_shot.dart';
import 'package:shutter/src/fonts/font_cache.dart';
import 'package:shutter/src/fonts/google_fonts.dart';
import 'package:shutter/src/project/project.dart';
import 'package:shutter/src/scan/candidate.dart';
import 'package:test/test.dart';

import '../helpers.dart';

Candidate candidate(String symbol, {String? error, int line = 1}) => Candidate(
  file: 'lib/a.dart',
  line: line,
  column: 1,
  symbol: symbol,
  annotationIndex: 0,
  annotation: r"const $i0.Preview(name: 'x')",
  target: '\$i1.$symbol',
  error: error,
);

SourceLibrary library(
  List<Candidate> candidates, {
  String file = 'lib/a.dart',
}) => SourceLibrary(
  file: file,
  imports: [
    r"import 'package:flutter/widget_previews.dart' as $i0;",
    r"import 'package:app/a.dart' as $i1;",
  ],
  candidates: candidates,
);

GeneratorConfig config(
  Project project, {
  List<SourceLibrary> libraries = const [],
  WidgetShot? widget,
  bool googleFonts = false,
  List<CachedFont> fonts = const [],
}) => GeneratorConfig(
  request: CaptureRequest(
    project: project,
    libraries: libraries,
    runDir: '/runs/r1',
    settleMs: 300,
    widget: widget,
  ),
  materialFontsDir: '/sdk/fonts',
  design: const DesignSupport(available: [], shell: null),
  googleFonts: googleFonts,
  fonts: fonts,
);

void main() {
  test('helperSource leaves out candidates with an error; null when none '
      'is left', () {
    final source = helperSource(
      library([candidate('a'), candidate('B.new'), candidate('c', error: 'x')]),
    )!;
    // Unprefixed, so a prefixed `dart:core` import does not hide `List`.
    expect(source, contains("import 'dart:core';\n"));
    expect(source, contains(r'target: $i1.a,'));
    expect(source, contains(r'target: $i1.B.new,'));
    expect(source, isNot(contains(r'target: $i1.c,')));
    expect(helperSource(library([candidate('a', error: 'x')])), isNull);
  });

  test('mainSource wraps in the project shell when there is one, and '
      'registers cached fonts', () {
    final root = createProject(files: {'lib/preview/shell.dart': ''});
    final withShell = mainSource(['l1'], config(Project.load(root)));
    expect(withShell, contains(r'shell: $shell.shell,'));
    expect(withShell, contains(r'...$s0.entries(),'));
    final bare = mainSource(const [], config(Project.load(createProject())));
    expect(bare, isNot(contains('shell:')));
    expect(bare, isNot(contains('fonts: [')));

    final withFonts = mainSource(
      const [],
      config(
        Project.load(createProject()),
        googleFonts: true,
        fonts: const [
          CachedFont(
            '/cache/abc.ttf',
            GoogleFontFile(
              family: 'Lobster',
              weight: 400,
              italic: false,
              hash: 'abc',
              length: 1,
            ),
          ),
        ],
      ),
    );
    expect(withFonts, contains('googleFonts: true,'));
    expect(withFonts, contains("asset: 'Lobster-Regular.ttf',"));
  });

  test('a --widget helper imports unprefixed, escapes the expression in the '
      'name, and ids by expression and imports', () {
    const sized = WidgetShot(
      source: r'Text("$x")',
      imports: ['package:app/a.dart'],
      size: (200, 56.5),
    );
    final source = sized.helperSource();
    expect(source, contains("import 'package:app/a.dart';\n"));
    expect(
      source,
      contains(
        r'''Preview(name: 'Text("\$x")', size: $ui.Size(200.0, 56.5))''',
      ),
    );
    expect(source, contains(r'target: () => Text("$x"),'));
    const other = WidgetShot(
      source: r'Text("$x")',
      imports: ['package:app/b.dart'],
    );
    expect(other.staticId, isNot(sized.staticId));
  });

  test('writeGeneratedTest adds the --widget helper', () {
    final project = Project.load(createProject());
    final path = writeGeneratedTest(
      config(
        project,
        widget: const WidgetShot(source: 'A()', imports: []),
      ),
    );
    expect(
      File(p.join(p.dirname(path), 'sources', 'widget.dart')).existsSync(),
      isTrue,
    );
    expect(
      File(path).readAsStringSync(),
      contains(r"import 'sources/widget.dart' as $s0;"),
    );
  });

  test('writeGeneratedTest writes .shutter/test/<run-id>/ afresh and '
      'leaves other runs alone', () {
    final project = Project.load(createProject());
    writeFiles(project.root, {
      '.shutter/test/r1/stale.dart': '',
      '.shutter/test/r0/other.dart': '',
    });
    final path = writeGeneratedTest(
      config(
        project,
        libraries: [
          library([candidate('a')]),
          library([candidate('b', error: 'x')], file: 'lib/b.dart'),
        ],
      ),
    );
    final dir = p.join(project.testDir, 'r1');
    expect(path, p.join(dir, 'shutter_test.dart'));
    expect(
      File(p.join(project.testDir, 'r0', 'other.dart')).existsSync(),
      isTrue,
    );
    final files = Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => p.relative(f.path, from: dir))
        .toSet();
    expect(files, {
      'shutter_test.dart',
      'shutter_harness.dart',
      'shutter_design.dart',
      p.join('sources', 'l0.dart'),
    });
    expect(
      File(p.join(dir, 'shutter_harness.dart')).readAsStringSync(),
      harnessText,
    );
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shutter/src/engine/engine.dart';
import 'package:shutter/src/engine/flutter_test_engine.dart';
import 'package:shutter/src/engine/widget_shot.dart';
import 'package:shutter/src/project/flutter_sdk.dart';
import 'package:shutter/src/project/project.dart';
import 'package:shutter/src/run/manifest.dart';
import 'package:shutter/src/scan/candidate.dart';
import 'package:test/test.dart';

import '../fonts/fixtures.dart';
import '../helpers.dart';

Candidate candidate(String file, String symbol, {String? error}) => Candidate(
  file: file,
  line: 2,
  column: 1,
  symbol: symbol,
  annotationIndex: 0,
  annotation: r'const $i0.Preview()',
  target: '\$i1.$symbol',
  error: error,
);

SourceLibrary library(String file, List<Candidate> candidates) =>
    SourceLibrary(file: file, imports: const [], candidates: candidates);

/// A `flutter test` stand-in: records calls and answers from [respond].
class FakeFlutter {
  FakeFlutter(this.respond);

  final ProcessResult Function(int call, List<String> args, String cwd) respond;
  final calls = <List<String>>[];
  final generated = <String>[];

  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    calls.add(arguments);
    generated.add(
      File(p.join(workingDirectory!, arguments[1])).readAsStringSync(),
    );
    return respond(calls.length - 1, arguments, workingDirectory);
  }
}

ProcessResult result(int code, {String stdout = '', String stderr = ''}) =>
    ProcessResult(0, code, stdout, stderr);

void writeResult(String runDir, Map<String, Object?> json) {
  File(p.join(runDir, '.results', '${json['id']}.json'))
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(json));
}

void main() {
  googleFontsTests();
  late Project project;
  late String runDir;

  setUp(() {
    project = Project.load(createProject());
    runDir = p.join(project.runsDir, 'r1');
    Directory(runDir).createSync(recursive: true);
  });

  CaptureRequest request(List<SourceLibrary> libraries) => CaptureRequest(
    project: project,
    libraries: libraries,
    runDir: runDir,
    settleMs: 300,
  );

  test('runs flutter test and collects per-shot results', () async {
    writeFiles(project.root, {'.dart_tool/package_config.json': '{}'});
    final fake = FakeFlutter((call, args, cwd) {
      writeResult(runDir, {
        'id': 'a.0',
        'name': 'a',
        'file': 'lib/a.dart',
        'line': 2,
        'status': 'ok',
        'png': 'a.0.png',
        'size': [200, 56],
      });
      writeFiles(runDir, {
        '.results/notes.txt': '',
        // Planned and finished: the result wins.
        '.results/a.0.planned': jsonEncode({
          'id': 'a.0',
          'name': 'a',
          'file': 'lib/a.dart',
          'line': 2,
          'status': 'error',
          'error': 'no result',
          'at': 'lib/a.dart:2',
        }),
        // Planned, never finished: the planned error stands.
        '.results/b.0.planned': jsonEncode({
          'id': 'b.0',
          'name': 'b',
          'file': 'lib/a.dart',
          'line': 5,
          'status': 'error',
          'error': 'no result',
          'at': 'lib/a.dart:5',
        }),
      });
      return result(1);
    });
    final engine = FlutterTestEngine(
      sdk: FlutterSdk('/sdk'),
      processRunner: fake.call,
    );
    final shots = await engine.capture(
      request([
        library('lib/a.dart', [
          candidate('lib/a.dart', 'a'),
          candidate('lib/a.dart', 'p', error: 'private'),
        ]),
      ]),
    );
    expect(fake.calls.single, [
      'test',
      p.join('.shutter', 'test', 'r1', 'shutter_test.dart'),
      '--reporter',
      'json',
      '--no-pub',
    ]);
    expect(fake.generated.single, contains('settleMs: 300,'));
    expect(
      (shots.first.id, shots.first.status),
      ('${candidate('lib/a.dart', 'p').staticId}.0', ShotStatus.error),
    );
    expect(
      shots.skip(1).map((s) => (s.id, s.status)),
      unorderedEquals([('a.0', ShotStatus.ok), ('b.0', ShotStatus.error)]),
    );
    final planned = shots.singleWhere((s) => s.id == 'b.0');
    expect((planned.error, planned.at), ('no result', 'lib/a.dart:5'));
    expect(shots.singleWhere((s) => s.id == 'a.0').size, (200.0, 56.0));
    expect(shots.first.error, 'private');
    expect(shots.first.at, 'lib/a.dart:2:1');
    expect(shots.first.name, 'p');
    expect(Directory(p.join(runDir, '.results')).existsSync(), isFalse);
    expect(
      Directory(p.join(project.testDir, 'r1')).existsSync(),
      isFalse,
      reason: 'the generated test is deleted after the run',
    );
  });

  test('no tests registered (exit 79) means no shots', () async {
    final fake = FakeFlutter((call, args, cwd) => result(79));
    final shots = await FlutterTestEngine(
      sdk: FlutterSdk('/sdk'),
      processRunner: fake.call,
    ).capture(request(const []));
    expect(shots, isEmpty);
    expect(fake.calls.single, isNot(contains('--no-pub')));
  });

  test('a compile failure makes every shot an error with the first compiler '
      'error, without a retry', () async {
    final fake = FakeFlutter((call, args, cwd) {
      final errorEvent = jsonEncode({
        'type': 'error',
        'error':
            '/abs/lib/bad.dart:9:1: Error: Nope.\nlib/b.dart:1:1: Error: B.',
      });
      return result(1, stdout: '$errorEvent\n{"type":"done"}\nnot json\n[1]\n');
    });
    final shots =
        await FlutterTestEngine(
          sdk: FlutterSdk('/sdk'),
          processRunner: fake.call,
        ).capture(
          request([
            library('lib/good.dart', [candidate('lib/good.dart', 'g')]),
            library('lib/bad.dart', [candidate('lib/bad.dart', 'b')]),
          ]),
        );
    expect(fake.calls, hasLength(1));
    expect(
      {for (final s in shots) s.name: s.error},
      {
        'g': '/abs/lib/bad.dart:9:1: Error: Nope.',
        'b': '/abs/lib/bad.dart:9:1: Error: Nope.',
      },
    );
  });

  test('a long failure without a compiler error marks every candidate with '
      'its last 20 lines', () async {
    final fake = FakeFlutter(
      (call, args, cwd) => result(
        1,
        stdout: [for (var i = 0; i < 25; i++) 'line $i'].join('\n'),
      ),
    );
    final shots =
        await FlutterTestEngine(
          sdk: FlutterSdk('/sdk'),
          processRunner: fake.call,
        ).capture(
          request([
            library('lib/a.dart', [
              candidate('lib/a.dart', 'a'),
              candidate('lib/a.dart', 'b'),
            ]),
          ]),
        );
    expect(fake.calls, hasLength(1));
    expect(shots, hasLength(2));
    for (final shot in shots) {
      expect(shot.status, ShotStatus.error);
      expect(shot.error, startsWith('line 5\n'));
      expect(shot.error, endsWith('line 24'));
    }
  });

  test('a --widget that does not compile is an error shot, the same in '
      'every run', () async {
    const widget = WidgetShot(
      source: 'Missing()',
      imports: ['package:flutter/widgets.dart'],
    );
    final fake = FakeFlutter(
      (call, args, cwd) => result(
        1,
        stdout:
            '${p.dirname(args[1])}/sources/widget.dart:9:22: Error: Method '
            "not found: 'Missing'.",
      ),
    );
    Future<Shot> shoot(String runDir) async =>
        (await FlutterTestEngine(
              sdk: FlutterSdk('/sdk'),
              processRunner: fake.call,
            ).capture(
              CaptureRequest(
                project: project,
                libraries: const [],
                runDir: runDir,
                settleMs: 300,
                widget: widget,
              ),
            ))
            .single;
    final shot = await shoot(runDir);
    expect(fake.calls, hasLength(1));
    expect(fake.generated.single, contains(r'...$s0.entries(),'));
    expect(shot.id, '${widget.staticId}.0');
    expect(shot.name, 'Missing()');
    expect(shot.status, ShotStatus.error);
    expect(shot.error, "Method not found: 'Missing'.");
    expect((shot.file, shot.at), (null, null));

    final r2 = p.join(project.runsDir, 'r2');
    Directory(r2).createSync(recursive: true);
    expect((await shoot(r2)).error, shot.error);
  });

  test('testOutput and firstCompileError', () {
    expect(
      testOutput('{"message":"m"}\n\n', '{"error":"e","other":1}'),
      'm\ne',
    );
    String? first(String output) =>
        firstCompileError(output, root: '/app', generatedDir: '/app/.t/r1');
    expect(
      first('x\n  lib/a.dart:1:2: Error: E\nlib/b.dart:1:2: Error'),
      'lib/a.dart:1:2: Error: E',
    );
    expect(
      first('/app/lib/a.dart:1:2: Error: E'),
      '/app/lib/a.dart:1:2: Error: E',
    );
    expect(first('.t/r1/shutter_test.dart:3:4: Error: G '), 'G');
    expect(first('/app/.t/r1/sources/l0.dart:3:4: Error: G'), 'G');
    expect(first('lib/b.dart:1:2: Warning: W'), isNull);
  });
}

void googleFontsTests() {
  group('google_fonts', () {
    late Project project;
    late String runDir;
    final lobster = utf8.encode('lobster font');
    final noto = utf8.encode('noto font');
    late String gfRoot;

    setUp(() {
      project = Project.load(createProject());
      runDir = p.join(project.runsDir, 'r1');
      Directory(runDir).createSync(recursive: true);
      gfRoot = googleFontsPackage({'Lobster': lobster, 'NotoSansJP': noto});
      linkGoogleFonts(project.root, gfRoot);
    });

    CaptureRequest request() => CaptureRequest(
      project: project,
      libraries: [
        library('lib/a.dart', [candidate('lib/a.dart', 'a')]),
      ],
      runDir: runDir,
      settleMs: 300,
    );

    /// Reports every hash in [missing] that the generated test does not
    /// register yet.
    FakeFlutter flutterMissing(List<String> missing) =>
        FakeFlutter((call, args, cwd) {
          final generated = File(p.join(cwd, args[1])).readAsStringSync();
          final still = [
            for (final hash in missing)
              if (!generated.contains('$hash.ttf')) hash,
          ];
          writeResult(runDir, {
            'id': 'a.0',
            'name': 'a',
            'status': still.isEmpty ? 'ok' : 'error',
            'file': 'lib/a.dart',
            'line': 2,
            if (still.isNotEmpty) ...{
              'error':
                  'Exception: Failed to load font with url: '
                  'https://fonts.gstatic.com/s/a/${still.first}.ttf',
              // Where the harness found the failing text; the font error
              // replaces it with the preview.
              'at': 'lib/ui/card.dart:9:3',
              'missing_fonts': still,
            },
          });
          return result(0);
        });

    test('downloads every missing font, then captures again', () async {
      final fake = flutterMissing([hashOf(lobster), hashOf(noto)]);
      final fetched = <Uri>[];
      final shots = await FlutterTestEngine(
        sdk: FlutterSdk('/sdk'),
        processRunner: fake.call,
        fetchFont: (url) async {
          fetched.add(url);
          return Uint8List.fromList(
            url.path.contains(hashOf(lobster)) ? lobster : noto,
          );
        },
      ).capture(request());
      expect(fake.calls, hasLength(2));
      expect(fetched, hasLength(2));
      expect(fake.generated.first, contains('googleFonts: true,'));
      expect(fake.generated.last, contains("family: 'Lobster_regular',"));
      expect(fake.generated.last, contains("asset: 'NotoSansJP-Regular.ttf',"));
      expect(shots.single.status, ShotStatus.ok);

      // Cached now: one capture, no download.
      final again = flutterMissing([hashOf(lobster)]);
      await FlutterTestEngine(
        sdk: FlutterSdk('/sdk'),
        processRunner: again.call,
        fetchFont: (_) => fail('no download expected'),
      ).capture(request());
      expect(again.calls, hasLength(1));
    });

    test('asset-name failures (runtime fetching disabled) are resolved '
        'by file name', () async {
      final fake = FakeFlutter((call, args, cwd) {
        final generated = File(p.join(cwd, args[1])).readAsStringSync();
        final cached = generated.contains("asset: 'Lobster-Regular.ttf',");
        writeResult(runDir, {
          'id': 'a.0',
          'name': 'a',
          'status': cached ? 'ok' : 'error',
          if (!cached) ...{
            'error':
                'Exception: GoogleFonts.config.allowRuntimeFetching is '
                'false but font Lobster-Regular was not found in the '
                'application assets.',
            'missing_fonts': ['Lobster-Regular'],
          },
        });
        return result(0);
      });
      final shots = await FlutterTestEngine(
        sdk: FlutterSdk('/sdk'),
        processRunner: fake.call,
        fetchFont: (_) async => Uint8List.fromList(lobster),
      ).capture(request());
      expect(fake.calls, hasLength(2));
      expect(shots.single.status, ShotStatus.ok);
    });

    test('fonts that cannot be downloaded or are unknown become errors '
        'at the preview', () async {
      final unknown = 'f' * 64;
      final fake = flutterMissing([hashOf(lobster), unknown]);
      final shots = await FlutterTestEngine(
        sdk: FlutterSdk('/sdk'),
        processRunner: fake.call,
        fetchFont: (_) async => throw const SocketException('offline'),
      ).capture(request());
      expect(fake.calls, hasLength(1));
      final shot = shots.single;
      expect(shot.status, ShotStatus.error);
      expect(
        shot.error,
        startsWith(
          'google_fonts Lobster-Regular.ttf is not cached and could not be '
          'downloaded: download failed',
        ),
      );
      expect(shot.at, 'lib/a.dart:2');

      final onlyUnknown = await FlutterTestEngine(
        sdk: FlutterSdk('/sdk'),
        processRunner: flutterMissing([unknown]).call,
      ).capture(request());
      expect(
        onlyUnknown.single.error,
        'google_fonts file $unknown is unknown to the google_fonts package '
        'at $gfRoot',
      );
    });

    test('a font still missing after download is reported as not loaded, '
        'and rounds are bounded', () async {
      var call = 0;
      final hashes = [hashOf(lobster), hashOf(noto)];
      final fake = FakeFlutter((c, args, cwd) {
        call++;
        // Always reports the lobster file missing, as if loading it failed.
        writeResult(runDir, {
          'id': 'a.0',
          'name': 'a',
          'status': 'error',
          'error': 'boom',
          'missing_fonts': [hashes[0]],
        });
        return result(0);
      });
      final shots = await FlutterTestEngine(
        sdk: FlutterSdk('/sdk'),
        processRunner: fake.call,
        fetchFont: (url) async => Uint8List.fromList(lobster),
      ).capture(request());
      expect(call, 4);
      expect(
        shots.single.error,
        'google_fonts file ${hashes[0]} could not be loaded',
      );
    });
  });
}

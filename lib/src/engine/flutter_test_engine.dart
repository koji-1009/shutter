import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../fonts/font_cache.dart';
import '../fonts/google_fonts.dart';
import '../project/flutter_sdk.dart';
import '../project/process_runner.dart';
import '../run/manifest.dart';
import '../scan/candidate.dart';
import 'design.dart';
import 'engine.dart';
import 'generator.dart';

/// Captures after the first that may download google_fonts files. A font
/// can surface only once another loads (a style resolved later in the
/// build), so one retry is not always enough.
const _maxFontRounds = 3;

/// `flutter test` exits 79 when a suite registers no tests.
const _noTestsRan = 79;

/// Engine v1: generates a `flutter_test` file under
/// `.dart_tool/shutter/test/`, runs
/// it with `flutter test`, and deletes it.
class FlutterTestEngine implements Engine {
  FlutterTestEngine({
    required this.sdk,
    ProcessRunner? processRunner,
    this.fetchFont,
  }) : _run = processRunner ?? runProcess;

  final FlutterSdk sdk;
  final ProcessRunner _run;

  /// Downloads missing google_fonts files; [fetchUrl] when null.
  final FontFetcher? fetchFont;

  /// Captures; when google_fonts reports files missing from the cache,
  /// downloads them all and captures again, until nothing new can be
  /// fetched. Shots still missing a font become errors naming it.
  @override
  Future<List<Shot>> capture(CaptureRequest request) async {
    final googleFonts = request.project.packageRoot('google_fonts');
    final cache = FontCache(request.project.googleFontsDir, fetch: fetchFont);
    final design = DesignSupport.detect(request.project, sdk);
    var pass = await _capture(
      request,
      design,
      cache.list(),
      googleFonts: googleFonts != null,
    );
    if (googleFonts == null) return pass.shots;
    final known = <String, GoogleFontFile>{};
    final failures = <String, String>{};
    // Keys are file hashes, or `<Family>-<Variant>` asset names when the
    // project disallows runtime fetching.
    for (var round = 0; round < _maxFontRounds; round++) {
      final pending = {for (final hashes in pass.missingFonts.values) ...hashes}
          .difference(failures.keys.toSet());
      if (pending.isEmpty) break;
      if (known.isEmpty) {
        for (final font in scanGoogleFonts(googleFonts).values) {
          known[font.hash] = font;
          known[p.basenameWithoutExtension(font.assetName)] = font;
        }
      }
      var added = false;
      Future<void> fetch(String key) async {
        final font = known[key];
        if (font == null) {
          failures[key] =
              'google_fonts file $key is unknown to the google_fonts '
              'package at $googleFonts';
          return;
        }
        final reason = await cache.add(font);
        if (reason == null) {
          added = true;
        } else {
          failures[key] =
              'google_fonts ${font.assetName} is not cached and could '
              'not be downloaded: $reason';
        }
      }

      await Future.wait(pending.map(fetch));
      if (!added) break;
      pass = await _capture(request, design, cache.list(), googleFonts: true);
    }
    return [
      for (final shot in pass.shots)
        if (pass.missingFonts[shot.id]?.firstOrNull case final key?)
          shot.withError(
            failures[key] ?? 'google_fonts file $key could not be loaded',
          )
        else
          shot,
    ];
  }

  /// One capture. Returns the shots and, per shot id, the google_fonts
  /// files (hashes) that failed to load. When the generated test does not
  /// compile, every shot is an error carrying the first compiler error.
  Future<({List<Shot> shots, Map<String, Set<String>> missingFonts})> _capture(
    CaptureRequest request,
    DesignSupport design,
    List<CachedFont> fonts, {
    required bool googleFonts,
  }) async {
    final project = request.project;
    final shots = <Shot>[
      for (final library in request.libraries)
        for (final c in library.candidates)
          if (c.error case final error?) _candidateError(c, error),
    ];
    final testPath = writeGeneratedTest(
      GeneratorConfig(
        request: request,
        materialFontsDir: sdk.materialFontsDir,
        design: design,
        googleFonts: googleFonts,
        fonts: fonts,
      ),
    );
    final result = await _run(sdk.executable(), [
      'test',
      p.relative(testPath, from: project.root),
      '--reporter',
      'json',
      if (File(project.packageConfigPath).existsSync()) '--no-pub',
    ], workingDirectory: project.root);
    Directory(p.dirname(testPath)).deleteSync(recursive: true);
    final missingFonts = <String, Set<String>>{};
    final captured = _readResults(request.runDir, missingFonts);
    if (captured.isNotEmpty ||
        result.exitCode == 0 ||
        result.exitCode == _noTestsRan) {
      return (shots: [...shots, ...captured], missingFonts: missingFonts);
    }
    final output = testOutput('${result.stdout}', '${result.stderr}');
    final message =
        firstCompileError(
          output,
          root: project.root,
          generatedDir: p.dirname(testPath),
        ) ??
        _lastLines(output);
    return (
      shots: [
        ...shots,
        for (final library in request.libraries)
          for (final c in library.candidates)
            if (c.error == null) _candidateError(c, message),
        if (request.widget case final widget?)
          Shot(
            id: '${widget.staticId}.0',
            status: ShotStatus.error,
            name: widget.source,
            error: message,
          ),
      ],
      missingFonts: missingFonts,
    );
  }

  Shot _candidateError(Candidate c, String error) => Shot(
    id: '${c.staticId}.0',
    status: ShotStatus.error,
    file: c.file,
    line: c.line,
    name: c.symbol,
    error: error,
    at: '${c.file}:${c.line}:${c.column}',
  );

  /// Reads and removes `<runDir>/.results/`, collecting each shot's
  /// `missing_fonts` into [missingFonts]. A shot the harness planned
  /// (`<id>.planned`) but never finished (`<id>.json`) is reported with
  /// the planned error.
  List<Shot> _readResults(
    String runDir,
    Map<String, Set<String>> missingFonts,
  ) {
    final dir = Directory(p.join(runDir, '.results'));
    if (!dir.existsSync()) return const [];
    final results = <String, Map<String, Object?>>{};
    final planned = <String, Map<String, Object?>>{};
    for (final file in dir.listSync().whereType<File>()) {
      final target = switch (p.extension(file.path)) {
        '.json' => results,
        '.planned' => planned,
        _ => null,
      };
      if (target == null) continue;
      final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      target[json['id']! as String] = json;
    }
    dir.deleteSync(recursive: true);
    final shots = <Shot>[];
    for (final json in {...planned, ...results}.values) {
      final shot = Shot.fromJson(json);
      shots.add(shot);
      if (json['missing_fonts'] case final List<Object?> hashes) {
        missingFonts[shot.id] = hashes.cast<String>().toSet();
      }
    }
    return shots;
  }
}

/// Flattens `flutter test --reporter json` output: `error` and `message`
/// fields of JSON events, and every non-JSON line as-is.
String testOutput(String stdout, String stderr) {
  final lines = <String>[];
  for (final line in '$stdout\n$stderr'.split('\n')) {
    Object? event;
    try {
      event = jsonDecode(line);
    } on FormatException {
      event = null;
    }
    if (event is Map<String, Object?>) {
      for (final key in const ['error', 'message']) {
        if (event[key] case final String text) lines.add(text);
      }
    } else if (line.trim().isNotEmpty) {
      lines.add(line);
    }
  }
  return lines.join('\n');
}

/// The first `path:line:column: Error: message` in [output], or only its
/// message when the path (relative to [root]) is under [generatedDir]:
/// that file is gone after the run, and its path holds the run id.
/// The first error can follow `Compilation failed for testPath=...: ` on
/// its line, so it need not start one.
String? firstCompileError(
  String output, {
  required String root,
  required String generatedDir,
}) {
  final match = RegExp(
    r'(?:^|\s)(\S+?\.dart):\d+:\d+: Error: (.*)$',
    multiLine: true,
  ).firstMatch(output);
  if (match == null) return null;
  final generated = p.isWithin(generatedDir, p.join(root, match.group(1)!));
  return match.group(generated ? 2 : 0)!.trim();
}

String _lastLines(String output) {
  final lines = output.trim().split('\n');
  final tail = lines.length > 20 ? lines.sublist(lines.length - 20) : lines;
  return tail.join('\n');
}

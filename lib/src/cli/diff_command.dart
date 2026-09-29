import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../dart_literal.dart';
import '../diff/composite.dart';
import '../diff/diff_engine.dart';
import '../engine/engine.dart';
import '../engine/widget_shot.dart';
import '../project/project.dart';
import '../reporters/diff_reporter.dart';
import '../run/run_store.dart';
import '../run/timestamp_id.dart';
import '../shutter_exception.dart';
import 'context.dart';
import 'io_sinks.dart';

/// `shutter diff <run-a> <run-b>` — compares two runs pixel-wise.
class DiffCommand(final ShutterContext context) extends Command<int> {
  this {
    argParser
      ..addFlag(
        'images',
        negatable: false,
        help:
            'Also write an image marking the differing pixels in red for '
            'each changed entry, under .dart_tool/shutter/diffs/.',
      )
      ..addFlag(
        'composite',
        negatable: false,
        help:
            'Also write one image per changed entry holding its before, '
            'diff and after panels, to attach on its own.',
      )
      ..addOption(
        'direction',
        help:
            'How --composite lays the three panels out; auto puts a '
            'portrait shot side by side and a landscape one stacked.',
        allowed: ['auto', 'horizontal', 'vertical'],
        defaultsTo: 'auto',
      )
      ..addOption(
        'title',
        help:
            'Text drawn above the panels of every --composite image. '
            'Rendered by Flutter, so any script the host has a font for '
            'works; needs a Flutter SDK.',
      );
  }

  @override
  String get name => 'diff';

  @override
  String get description =>
      'Compare two runs (a directory, an id, latest, or latest~N); '
      'exit 0 unchanged, 1 changed.';

  @override
  String get invocation => 'shutter diff <run-a> <run-b>';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.length != 2) {
      throw ShutterException.usage('expected two runs: <run-a> <run-b>.');
    }
    final [a, b] = args.rest;
    final images = args.flag('images');
    final composite = args.flag('composite');
    final title = args.option('title');
    if (!composite && (title != null || args.wasParsed('direction'))) {
      throw ShutterException.usage('--direction and --title need --composite.');
    }
    final direction = CompositeDirection.values.byName(
      args.option('direction')!,
    );
    final project = context.project();
    final before = loadRun(project, a);
    final after = loadRun(project, b);
    final dir = images || composite
        ? createTimestampDir(project.diffsDir, context.clock())
        : null;
    final diff = diffRuns(
      before,
      after,
      dir: dir,
      images: images,
      composite: composite ? direction : null,
      titles: title == null
          ? const {}
          : await _titles(project, before, after, title, direction, dir!),
    );
    reportDiff(diff, dir, ShutterIO.stdoutSink);
    return diff.exitCode;
  }

  /// Renders [text] once for every size of sheet the diff will write, to
  /// the room that sheet has between its gutters and at the size of its
  /// captions, keyed by [CompositeLayout.title].
  ///
  /// Empty when no entry can take a sheet, so that a diff needing no title
  /// needs no Flutter either, and a render that failed is reported and
  /// leaves those sheets untitled.
  Future<Map<(int, int), img.Image>> _titles(
    Project project,
    StoredRun before,
    StoredRun after,
    String text,
    CompositeDirection direction,
    String dir,
  ) async {
    final sheets = {
      for (final layout in compositeLayouts(
        before,
        after,
        direction: direction,
      ))
        layout.title,
    };
    if (sheets.isEmpty) return const {};
    requireFlutterTest(project);
    final sdk = context.sdk();
    final engine = context.engineFactory(sdk);
    final titles = <(int, int), img.Image>{};
    for (final sheet in sheets) {
      final (room, fontBase) = sheet;
      // Its own directory, because the engine leaves the shot's PNG and
      // its results behind, and keys the generated test on the
      // directory's name.
      final scratch = p.join(project.diffsDir, '.${p.basename(dir)}-$room');
      Directory(scratch).createSync(recursive: true);
      try {
        final shots = await engine.capture(
          CaptureRequest(
            project: project,
            libraries: const [],
            // The sheet is physical pixels and a shot is logical, at the
            // harness's device pixel ratio of 2. The text is laid out in
            // exactly the room it will be drawn into, at the size of that
            // sheet's captions, so it is neither scaled nor re-wrapped
            // afterwards; an unbounded height lets it take the lines it
            // needs.
            widget: WidgetShot(
              source:
                  'Text(${dartString(text)}, style: TextStyle('
                  'fontSize: ${fontBase / 2}, color: Color(0xFF000000)))',
              imports: const ['package:flutter/widgets.dart'],
              size: (room / 2, double.infinity),
            ),
            runDir: scratch,
            settleMs: 0,
          ),
        );
        final png = switch (shots) {
          [final shot, ...] when shot.png != null => img.decodePng(
            File(p.join(scratch, shot.png!)).readAsBytesSync(),
          ),
          _ => null,
        };
        if (png != null) {
          titles[sheet] = png;
          // The text was laid out in the room it will be drawn into, so
          // its glyphs are as tall as the lines it took: one line of them
          // is about the font's own size, two are more than half again.
          if (img.trim(png).height > fontBase * 1.5) {
            ShutterIO.stderrSink.writeln(
              '--title does not fit one line on the ${room}px sheets; '
              'a shorter one would.',
            );
          }
        } else {
          ShutterIO.stderrSink.writeln(
            '--title was not drawn for the ${room}px sheets: '
            '${shots.firstOrNull?.error ?? 'no image'}',
          );
        }
      } finally {
        Directory(scratch).deleteSync(recursive: true);
      }
    }
    return titles;
  }
}

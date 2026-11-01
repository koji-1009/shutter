import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../cli/context.dart';
import '../dart_literal.dart';
import '../diff/composite.dart';
import '../diff/diff_engine.dart';
import '../diff/run_diff.dart';
import '../engine/engine.dart';
import '../engine/widget_shot.dart';
import '../project/project.dart';
import '../run/run_store.dart';
import '../run/timestamp_id.dart';
import '../shutter_exception.dart';
import 'diff.dart';

/// Compares the runs [before] and [after] as [diff] does, in the project
/// at or above the working directory of [context]. Returns the
/// comparison; the directory the images went into, when [images] or
/// [composite] asked for any; and why the title is missing from, or does
/// not fit, some sheets. Throws a [ShutterException] when a run is not
/// found, or a title is asked for and there is no Flutter SDK to draw it.
/// `shutter diff` reports the comparison; [diff] returns it as a
/// [ShotDiff].
Future<({RunDiff diff, String? dir, List<String> warnings})> compare(
  ShutterContext context,
  String before,
  String after, {
  bool images = false,
  DiffComposite? composite,
}) async {
  final project = context.project();
  final workingDirectory = context.workingDirectory;
  final beforeRun = loadRun(
    project,
    before,
    workingDirectory: workingDirectory,
  );
  final afterRun = loadRun(project, after, workingDirectory: workingDirectory);
  final dir = images || composite != null
      ? createTimestampDir(project.diffsDir, context.clock())
      : null;
  final warnings = <String>[];
  final titles = switch (composite) {
    DiffComposite(:final direction, title: final title?) => await _titles(
      context,
      project,
      beforeRun,
      afterRun,
      title,
      direction,
      dir!,
      warnings,
    ),
    _ => const <(int, int), img.Image>{},
  };
  final diff = diffRuns(
    beforeRun,
    afterRun,
    dir: dir,
    images: images,
    composite: composite?.direction,
    titles: titles,
  );
  return (diff: diff, dir: dir, warnings: warnings);
}

/// Renders [text] once for every size of sheet the diff will write, to
/// the room that sheet has between its gutters and at the size of its
/// captions, keyed by [CompositeLayout.title]. Adds to [warnings] why a
/// title is missing from, or does not fit, some sheets.
///
/// Empty when no entry can take a sheet, so that a diff needing no title
/// needs no Flutter either, and a render that failed leaves those sheets
/// untitled.
Future<Map<(int, int), img.Image>> _titles(
  ShutterContext context,
  Project project,
  StoredRun before,
  StoredRun after,
  String text,
  CompositeDirection direction,
  String dir,
  List<String> warnings,
) async {
  final sheets = {
    for (final layout in compositeLayouts(before, after, direction: direction))
      layout.title,
  };
  if (sheets.isEmpty) return const {};
  requireFlutterTest(project);
  final sdk = context.sdk();
  final engine = context.engineFactory(sdk);
  final titles = <(int, int), img.Image>{};
  for (final sheet in sheets) {
    final (room, fontBase) = sheet;
    // Its own directory, because the engine leaves the shot's PNG and its
    // results behind, and keys the generated test on the directory's
    // name.
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
        // The text was laid out in the room it will be drawn into, so its
        // glyphs are as tall as the lines it took: one line of them is
        // about the font's own size, two are more than half again.
        if (img.trim(png).height > fontBase * 1.5) {
          warnings.add(
            'The title does not fit one line on the ${room}px sheets; a '
            'shorter one would.',
          );
        }
      } else {
        warnings.add(
          'The title was not drawn for the ${room}px sheets: '
          '${shots.firstOrNull?.error ?? 'no image'}',
        );
      }
    } finally {
      Directory(scratch).deleteSync(recursive: true);
    }
  }
  return titles;
}

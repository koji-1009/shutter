import 'package:args/command_runner.dart';

import '../api/compare.dart';
import '../api/diff.dart';
import '../diff/composite.dart';
import '../reporters/diff_reporter.dart';
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
    final composite = args.flag('composite');
    final title = args.option('title');
    if (!composite && (title != null || args.wasParsed('direction'))) {
      throw ShutterException.usage('--direction and --title need --composite.');
    }
    final (:diff, :dir, :warnings) = await compare(
      context,
      a,
      b,
      images: args.flag('images'),
      composite: composite
          ? DiffComposite(
              direction: CompositeDirection.values.byName(
                args.option('direction')!,
              ),
              title: title,
            )
          : null,
    );
    warnings.forEach(ShutterIO.stderrSink.writeln);
    reportDiff(diff, dir, ShutterIO.stdoutSink);
    return diff.exitCode;
  }
}

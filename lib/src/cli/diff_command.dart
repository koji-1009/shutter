import 'package:args/command_runner.dart';

import '../diff/diff_engine.dart';
import '../reporters/diff_reporter.dart';
import '../run/run_store.dart';
import '../run/timestamp_id.dart';
import '../shutter_exception.dart';
import 'context.dart';
import 'io_sinks.dart';

/// `shutter diff <run-a> <run-b>` — compares two runs pixel-wise.
class DiffCommand(final ShutterContext context) extends Command<int> {
  this {
    argParser.addFlag(
      'images',
      negatable: false,
      help:
          'Also write an image marking the differing pixels in red for '
          'each changed entry, under .dart_tool/shutter/diffs/.',
    );
  }

  @override
  String get name => 'diff';

  @override
  String get description => 'Compare two runs; exit 0 unchanged, 1 changed.';

  @override
  String get invocation => 'shutter diff <run-a> <run-b>';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.length != 2) {
      throw ShutterException.usage('expected two runs: <run-a> <run-b>.');
    }
    final [a, b] = args.rest;
    final project = context.project();
    final before = loadRun(project, a);
    final after = loadRun(project, b);
    final imagesDir = args.flag('images')
        ? createTimestampDir(project.diffsDir, context.clock())
        : null;
    final diff = diffRuns(before, after, imagesDir: imagesDir);
    reportDiff(diff, imagesDir, ShutterIO.stdoutSink);
    return diff.exitCode;
  }
}

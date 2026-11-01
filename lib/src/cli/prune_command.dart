import 'package:args/command_runner.dart';

import '../api/prune.dart';
import '../reporters/prune_reporter.dart';
import '../shutter_exception.dart';
import 'context.dart';
import 'io_sinks.dart';
import 'shot_options.dart';

/// `shutter prune --keep <n>` — deletes every run but the newest.
class PruneCommand(final ShutterContext context) extends Command<int> {
  this {
    argParser.addOption(
      'keep',
      help:
          'How many of the newest runs to keep, e.g. 1; 0 deletes every '
          'run. Required.',
    );
  }

  @override
  String get name => 'prune';

  @override
  String get description =>
      'Delete every run under .dart_tool/shutter/runs/ but the newest '
      '--keep <n>, whoever shot them.';

  @override
  String get invocation => 'shutter prune --keep <n>';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.isNotEmpty) {
      throw ShutterException.usage('prune takes no arguments, only --keep.');
    }
    // Checked here rather than by the parser, whose mandatory options
    // throw only when read.
    if (!args.wasParsed('keep')) {
      throw ShutterException.usage('Give --keep <n>, the runs to keep.');
    }
    final keep = parseCount(args, 'keep');
    final result = prune(context.workingDirectory, keep: keep);
    reportPrune(
      removed: result.removed,
      kept: result.kept,
      sink: ShutterIO.stdoutSink,
    );
    return 0;
  }
}

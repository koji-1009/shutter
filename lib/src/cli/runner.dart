import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../shutter_exception.dart';
import '../version.dart';

import 'agent_text.dart';
import 'context.dart';
import 'diff_command.dart';
import 'doctor_command.dart';
import 'init_command.dart';
import 'io_sinks.dart';
import 'manual_text.dart';
import 'shot_command.dart';
import 'text_command.dart';

CommandRunner<int> buildCommandRunner([ShutterContext? context]) {
  final ctx = context ?? ShutterContext();
  return _ShutterRunner()
    ..argParser.addFlag(
      'version',
      negatable: false,
      help: 'Print the shutter version and exit.',
    )
    ..addCommand(
      TextCommand(
        name: 'agent',
        description: 'Print the step-by-step playbook for AI agents.',
        text: agentText,
      ),
    )
    ..addCommand(
      TextCommand(
        name: 'manual',
        description:
            'Print the concepts: shots, drawing model, engine, ids, '
            'exit codes, output.',
        text: manualText,
      ),
    )
    ..addCommand(DoctorCommand(ctx))
    ..addCommand(InitCommand(ctx))
    ..addCommand(ShotCommand(ctx))
    ..addCommand(DiffCommand(ctx));
}

class _ShutterRunner extends CommandRunner<int> {
  _ShutterRunner()
    : super('shutter', 'Express a change to a Flutter widget as an image.');

  @override
  void printUsage() => ShutterIO.stdoutSink.writeln(usage);

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults.command == null && topLevelResults.flag('version')) {
      ShutterIO.stdoutSink.writeln('shutter $packageVersion');
      return 0;
    }
    try {
      return await super.runCommand(topLevelResults);
    } on ShutterException catch (e) {
      if (e.exitCode != 64) rethrow;
      // An argument a command rejects reads like one the parser rejects:
      // the message, then the command's usage, on stderr.
      final command = commands[topLevelResults.command!.name]!;
      throw UsageException(e.toString(), command.usage);
    }
  }

  @override
  String get usageFooter =>
      '\nAI agents: run `shutter agent` first — it is the step-by-step '
      'playbook. `shutter manual` is the conceptual reference.';
}

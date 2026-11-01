import 'package:args/command_runner.dart';

import '../api/doctor.dart';
import 'context.dart';
import 'io_sinks.dart';
import 'shot_options.dart';

/// `shutter doctor` — checks the SDK, its font cache, and the project's
/// shell.
/// Exits 1 when any check fails; warnings do not change the exit code.
class DoctorCommand(final ShutterContext context) extends Command<int> {
  this {
    argParser.addOption('shell', help: shellHelp);
  }

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check the Flutter SDK, its font cache, and the project shell.';

  @override
  Future<int> run() async {
    final checks = checkSetup(context, shell: argResults!.option('shell'));
    for (final check in checks) {
      final tag = switch (check.level) {
        CheckLevel.ok => '[OK]  ',
        CheckLevel.warn => '[WARN]',
        CheckLevel.fail => '[FAIL]',
      };
      ShutterIO.stdoutSink.writeln('$tag ${check.message}');
      if (check.hint case final hint?) {
        ShutterIO.stdoutSink.writeln('       $hint');
      }
    }
    return checks.any((c) => c.level == CheckLevel.fail) ? 1 : 0;
  }
}

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';

import 'cli/context.dart';
import 'cli/io_sinks.dart';
import 'cli/runner.dart';
import 'shutter_exception.dart';

/// Process entrypoint. Wraps the [CommandRunner] in a guarded zone so
/// uncaught errors surface a deterministic, sysexits-aligned exit code
/// rather than crashing the VM:
///
/// - [ShutterException]         → its own code (`78 EX_CONFIG` by default)
/// - `UsageException` (bad CLI) → `64 EX_USAGE`
/// - any other uncaught error   → `70 EX_SOFTWARE`
Future<void> runApp(List<String> arguments) async {
  await runZonedGuarded(() async {
    exitCode = await runShutter(arguments);
  }, handleUncaughtZoneError);
}

/// Runs one CLI invocation against [context] and returns its exit code,
/// printing expected failures to stderr.
Future<int> runShutter(
  List<String> arguments, [
  ShutterContext? context,
]) async {
  try {
    return await buildCommandRunner(context).run(arguments) ?? 0;
  } on ShutterException catch (e) {
    ShutterIO.stderrSink.writeln(e.toString());
    return e.exitCode;
  } on UsageException catch (e) {
    ShutterIO.stderrSink.writeln(e.toString());
    return 64;
  }
}

/// Surfaces an unhandled async error from the [runApp] zone as an
/// `EX_SOFTWARE` exit. A reader that closed the pipe early
/// (`shutter diff ... | grep -q changed`) is not an error: the rest of
/// the output has nowhere to go, and the command's exit code stands.
void handleUncaughtZoneError(Object error, StackTrace stack) {
  if (_isBrokenPipe(error)) return;
  ShutterIO.stderrSink.writeln('Unhandled error: $error\n$stack');
  exitCode = 70;
}

/// `EPIPE`, as a write to stdout reports it.
bool _isBrokenPipe(Object error) => switch (error) {
  FileSystemException(:final osError?) ||
  SocketException(:final osError?) => osError.errorCode == 32,
  _ => false,
};

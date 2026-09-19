import 'package:args/command_runner.dart';

import 'io_sinks.dart';

/// A command that prints a document shipped in the binary.
class TextCommand({
  @override required final String name,
  @override required final String description,

  /// Mirror of a file under `doc/`, kept byte-identical by a test.
  required final String text,
}) extends Command<int> {
  @override
  Future<int> run() async {
    ShutterIO.stdoutSink.write(text);
    return 0;
  }
}

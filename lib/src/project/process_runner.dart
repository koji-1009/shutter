import 'dart:convert';
import 'dart:io';

/// Seam over running a process, so commands can be tested without a
/// Flutter SDK on the machine. [onStdoutLine] receives each line of
/// stdout as the process writes it.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  void Function(String line)? onStdoutLine,
});

/// Runs [executable] to its exit, collecting stdout as lines and stderr
/// as it is.
Future<ProcessResult> runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  void Function(String line)? onStdoutLine,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: Platform.isWindows,
  );
  final stderr = process.stderr.transform(systemEncoding.decoder).join();
  final stdout = StringBuffer();
  await process.stdout
      .transform(systemEncoding.decoder)
      .transform(const LineSplitter())
      .forEach((line) {
        stdout.writeln(line);
        onStdoutLine?.call(line);
      });
  return ProcessResult(
    process.pid,
    await process.exitCode,
    '$stdout',
    await stderr,
  );
}

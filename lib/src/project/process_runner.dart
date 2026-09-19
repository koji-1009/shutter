import 'dart:io';

/// Seam over `Process.run`, so commands can be tested without a Flutter
/// SDK on the machine.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

Future<ProcessResult> runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) => Process.run(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  runInShell: Platform.isWindows,
);

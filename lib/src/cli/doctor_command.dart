import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../project/flutter_sdk.dart';
import '../project/project.dart';
import '../shutter_exception.dart';
import 'context.dart';
import 'io_sinks.dart';

/// Oldest Flutter release with `package:flutter/widget_previews.dart` in
/// the shape shutter generates code for.
const minimumFlutter = (3, 47, 0);

enum CheckLevel { ok, warn, fail }

/// One line of the doctor report.
class const Check(
  final CheckLevel level,
  final String message, [
  final String? hint,
]);

/// `shutter doctor` — checks the SDK, its font cache, and the project's
/// shell.
/// Exits 1 when any check fails; warnings do not change the exit code.
class DoctorCommand(final ShutterContext context) extends Command<int> {
  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check the Flutter SDK, its font cache, and the project shell.';

  @override
  Future<int> run() async {
    final checks = [
      ..._sdkChecks(FlutterSdk.locate(environment: context.environment)),
      ..._projectChecks(),
    ];
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

  List<Check> _sdkChecks(FlutterSdk? sdk) {
    if (sdk == null) {
      return const [
        Check(CheckLevel.fail, 'Flutter SDK not found', flutterSdkHint),
      ];
    }
    final version = sdk.version;
    final (major, minor, patch) = minimumFlutter;
    final minimum = '$major.$minor.$patch';
    return [
      if (version == null)
        Check(
          CheckLevel.warn,
          'Flutter SDK at ${sdk.root}: version unknown',
          'run `flutter --version` once so the SDK writes its version file',
        )
      else if (isAtLeast(version, minimumFlutter))
        Check(CheckLevel.ok, 'Flutter $version at ${sdk.root}')
      else
        Check(
          CheckLevel.fail,
          'Flutter $version at ${sdk.root}: shutter needs $minimum or newer',
        ),
      if (_hasRoboto(sdk.materialFontsDir))
        Check(CheckLevel.ok, 'font cache: ${sdk.materialFontsDir}')
      else
        Check(
          CheckLevel.warn,
          'font cache missing: ${sdk.materialFontsDir}',
          'run `flutter precache`; without it text renders in the test font',
        ),
    ];
  }

  bool _hasRoboto(String dir) =>
      Directory(dir).existsSync() &&
      Directory(dir)
          .listSync()
          .any((e) => p.basename(e.path).startsWith('Roboto-'));

  List<Check> _projectChecks() {
    final Project project;
    try {
      project = context.project();
    } on ShutterException catch (e) {
      return [Check(CheckLevel.fail, e.message)];
    }
    return [
      Check(CheckLevel.ok, 'project ${project.name} at ${project.root}'),
      if (project.shellPath case final shell?)
        Check(CheckLevel.ok, 'shell ${project.relative(shell)}')
      else
        const Check(
          CheckLevel.warn,
          'no shell.dart; shots get the default shell',
          'run `shutter init` to write one',
        ),
    ];
  }
}

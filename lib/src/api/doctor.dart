import 'dart:io';

import 'package:path/path.dart' as p;

import '../cli/context.dart';
import '../project/flutter_sdk.dart';
import '../project/project.dart';
import '../shutter_exception.dart';
import 'shot.dart';

/// Oldest Flutter release with `package:flutter/widget_previews.dart` in
/// the shape shutter generates code for.
const minimumFlutter = (3, 47, 0);

/// How a [DoctorCheck] came out.
enum CheckLevel {
  /// Ready to shoot.
  ok,

  /// Shots work, but may not look as they should.
  warn,

  /// Shots will not work until it is fixed.
  fail,
}

/// One line of [doctor]'s report.
final class const DoctorCheck(
  final CheckLevel level,

  /// What was checked, and what was found, e.g. `Flutter 3.47.0 at
  /// /path/to/flutter`.
  final String message, {

  /// What to do about a warning or a failure, e.g. `run \`flutter
  /// precache\``.
  final String? hint,
}) {
  @override
  bool operator ==(Object other) =>
      other is DoctorCheck &&
      other.level == level &&
      other.message == message &&
      other.hint == hint;

  @override
  int get hashCode => Object.hash(level, message, hint);

  @override
  String toString() =>
      'DoctorCheck(${['level: ${level.name}', 'message: $message', if (hint != null) 'hint: $hint'].join(', ')})';
}

/// Checks what shooting the Flutter project at or above [projectDir]
/// needs, as `shutter doctor` does: the Flutter SDK and its version, its
/// font cache, the project, and its shell, [shell] (relative to
/// [projectDir], or absolute) when given. Returns the checks in the order
/// of the report; a [CheckLevel.fail] among them means [shot] will not
/// work until it is fixed, and `shutter doctor` exits 1.
List<DoctorCheck> doctor(String projectDir, {String? shell}) =>
    checkSetup(ShutterContext(workingDirectory: projectDir), shell: shell);

/// [doctor] against [context].
List<DoctorCheck> checkSetup(ShutterContext context, {String? shell}) => [
  ..._sdkChecks(FlutterSdk.locate(environment: context.environment)),
  ..._projectChecks(context, shell),
];

List<DoctorCheck> _sdkChecks(FlutterSdk? sdk) {
  if (sdk == null) {
    return const [
      DoctorCheck(
        CheckLevel.fail,
        'Flutter SDK not found',
        hint: flutterSdkHint,
      ),
    ];
  }
  final version = sdk.version;
  final (major, minor, patch) = minimumFlutter;
  final minimum = '$major.$minor.$patch';
  return [
    if (version == null)
      DoctorCheck(
        CheckLevel.warn,
        'Flutter SDK at ${sdk.root}: version unknown',
        hint: 'run `flutter --version` once so the SDK writes its version file',
      )
    else if (isAtLeast(version, minimumFlutter))
      DoctorCheck(CheckLevel.ok, 'Flutter $version at ${sdk.root}')
    else
      DoctorCheck(
        CheckLevel.fail,
        'Flutter $version at ${sdk.root}: shutter needs $minimum or newer',
      ),
    if (_hasRoboto(sdk.materialFontsDir))
      DoctorCheck(CheckLevel.ok, 'font cache: ${sdk.materialFontsDir}')
    else
      DoctorCheck(
        CheckLevel.warn,
        'font cache missing: ${sdk.materialFontsDir}',
        hint:
            'run `flutter precache`; without it text renders in the test font',
      ),
  ];
}

bool _hasRoboto(String dir) =>
    Directory(dir).existsSync() &&
    Directory(dir)
        .listSync()
        .any((e) => p.basename(e.path).startsWith('Roboto-'));

List<DoctorCheck> _projectChecks(ShutterContext context, String? shell) {
  final Project project;
  try {
    project = context.project();
  } on ShutterException catch (e) {
    return [DoctorCheck(CheckLevel.fail, e.message)];
  }
  final given = shell == null
      ? null
      : p.normalize(p.join(context.workingDirectory, shell));
  return [
    DoctorCheck(CheckLevel.ok, 'project ${project.name} at ${project.root}'),
    if (given != null)
      File(given).existsSync()
          ? DoctorCheck(CheckLevel.ok, 'shell ${project.shown(given)}')
          : DoctorCheck(
              CheckLevel.fail,
              'shell ${project.shown(given)} does not exist',
              hint: 'run `shutter init --shell $shell` to write one',
            )
    else if (project.shellPath case final path?)
      DoctorCheck(CheckLevel.ok, 'shell ${project.relative(path)}')
    else
      const DoctorCheck(
        CheckLevel.warn,
        'no shell.dart; shots get the default shell',
        hint: 'run `shutter init` to write one',
      ),
  ];
}

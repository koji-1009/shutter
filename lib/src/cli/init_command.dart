import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../engine/design.dart';

import 'context.dart';
import 'io_sinks.dart';
import 'shot_options.dart';

/// Written by `shutter init` when the project has no shell yet, against
/// the library the default shell would use ([shellLibrary]).
String shellTemplate(Set<String> dependencies) {
  final library = shellLibrary(dependencies, (_) => true)!;
  final app = library.isMaterial ? _materialApp : _cupertinoApp;
  return '''
import '${library.uri}';

/// App-level ambient for every shot without its own `wrapper`: app
/// widget, theme, router, providers, fake services.
/// `shutter shot` renders each such shot as `shell(shot)`; this function
/// replaces shutter's default, so it decides what surrounds the shot. An
/// app with its own design system returns its own app widget instead
/// (for example a WidgetsApp).
///
/// In the preview dir this file is committed, so every clone and CI shoot
/// with the same ambient. A shell made for one task and not meant to be
/// committed goes under .dart_tool/ instead (`shutter init --shell
/// .dart_tool/shutter/shell.dart`), named with `shutter shot --shell`.
/// Import the app with package: URIs there.
$app''';
}

const _materialApp = '''
Widget shell(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  // Use the app's themes so shots match the app:
  // theme: appTheme,
  // darkTheme: appDarkTheme,
  // A Material surface under the shot, as shutter's default shell has.
  home: Material(child: child),
);
''';

const _cupertinoApp = '''
Widget shell(Widget child) => CupertinoApp(
  debugShowCheckedModeBanner: false,
  // Use the app's theme so shots match the app:
  // theme: appTheme,
  home: child,
);
''';

/// `shutter init` — writes the shell template, unless the project has
/// one.
class InitCommand(final ShutterContext context) extends Command<int> {
  this {
    argParser.addOption('shell', help: shellHelp);
  }

  @override
  String get name => 'init';

  @override
  String get description => 'Write <preview dir>/shell.dart, or --shell.';

  @override
  Future<int> run() async {
    final project = context.project();
    final path = switch (argResults!.option('shell')) {
      final option? => shellOptionPath(option, context.workingDirectory),
      null => p.join(project.previewDir, 'shell.dart'),
    };
    if (File(path).existsSync()) {
      ShutterIO.stdoutSink.writeln(
        'kept     ${project.shown(path)} (already exists)',
      );
    } else {
      File(path)
        ..createSync(recursive: true)
        ..writeAsStringSync(shellTemplate(project.dependencies));
      ShutterIO.stdoutSink.writeln('wrote    ${project.shown(path)}');
    }
    return 0;
  }
}

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../engine/engine.dart';
import '../project/project.dart';
import '../reporters/shot_reporter.dart';
import '../run/manifest.dart';
import '../run/timestamp_id.dart';
import '../scan/scanner.dart';
import '../shutter_exception.dart';
import 'context.dart';
import 'io_sinks.dart';
import 'shot_options.dart';

/// `shutter shot` — renders the previews of the named files, or one
/// `--widget`, into a new run.
class ShotCommand(final ShutterContext context) extends Command<int> {
  this {
    argParser
      ..addOption(
        'widget',
        help:
            'Shoot this widget expression instead of preview files, '
            'e.g. \'PrimaryButton(label: "OK")\'.',
      )
      ..addMultiOption(
        'import',
        help:
            'File (under lib/) or package: URI the --widget needs imported. '
            'Repeatable; package:flutter/widgets.dart is always imported.',
      )
      ..addOption(
        'size',
        help: 'Logical size of the --widget shot, e.g. 390x844.',
      )
      ..addOption(
        'settle',
        help:
            'Milliseconds pumped once before capture, and again, in 16 ms '
            'frames, after each action.',
        defaultsTo: '300',
      )
      ..addOption('shell', help: shellHelp)
      ..addMultiOption(
        'tap',
        help:
            'Tap this widget of every shot before the capture: '
            '$targetHelp. Repeatable; taps and --enter run in the order '
            'given.',
        splitCommas: false,
      )
      ..addMultiOption(
        'enter',
        help:
            'Enter text into this text field, as <target>=<text>, e.g. '
            'key:name=Koji. Repeatable.',
        splitCommas: false,
      )
      // Multi-options, so that a second --press is rejected rather than
      // silently replacing the first.
      ..addMultiOption(
        'press',
        help: 'Hold a pointer down on this widget through the capture.',
        splitCommas: false,
      )
      ..addMultiOption(
        'hover',
        help: 'Keep a mouse pointer over this widget through the capture.',
        splitCommas: false,
      )
      ..addMultiOption(
        'focus',
        help:
            'Give this widget keyboard focus, highlighted as with a '
            'keyboard.',
        splitCommas: false,
      )
      ..addOption(
        'capture',
        help:
            'What the PNG holds: the preview, or the whole screen (the '
            'viewport, with menus and dialogs above the preview).',
        allowed: ['preview', 'screen'],
        defaultsTo: 'preview',
      )
      ..addOption(
        'viewport',
        help:
            'Logical size of the screen for --capture screen, e.g. 390x844; '
            'the preview sits at its top left.',
      );
  }

  @override
  String get name => 'shot';

  @override
  String get description =>
      'Render the previews in the named files, or one --widget, to PNG as a '
      'new run.';

  @override
  String get invocation =>
      'shutter shot <preview-file>... | shutter shot --widget <expression>';

  @override
  Future<int> run() async {
    final args = argResults!;
    final settle = parseCount(args, 'settle');
    final source = args.option('widget');
    final imports = args.multiOption('import');
    final size = switch (args.option('size')) {
      final raw? => parseSize(raw),
      null => null,
    };
    final actions = parseActions(args);
    final screen = args.option('capture') == 'screen';
    final viewport = switch (args.option('viewport')) {
      final raw? => parseSize(raw, name: 'viewport'),
      null => null,
    };
    final files = args.rest;
    if (source == null && (imports.isNotEmpty || size != null)) {
      throw ShutterException.usage('--import and --size need --widget.');
    }
    if (viewport != null && !screen) {
      throw ShutterException.usage('--viewport needs --capture screen.');
    }
    if ((source == null) == files.isEmpty) {
      throw ShutterException.usage(
        'Name the preview files to shoot, or give --widget; not both.',
      );
    }
    final project = context.project();
    if (!project.hasFlutterTest) {
      throw const ShutterException(
        'flutter_test is not in dev_dependencies; add it (`$flutterTestHint`).',
      );
    }
    final shell = resolveShell(
      project,
      args.option('shell'),
      workingDirectory: context.workingDirectory,
    );
    final sdk = context.sdk();
    final widget = switch (source) {
      final source? => parseWidgetShot(
        project,
        source: source,
        imports: imports,
        size: size,
        workingDirectory: context.workingDirectory,
      ),
      null => null,
    };
    final paths = [
      for (final file in files)
        libFile(
          project,
          file,
          workingDirectory: context.workingDirectory,
          what: 'preview file',
        ),
    ];
    final libraries = await Scanner(
      project,
      sdkPath: sdk.dartSdkPath,
    ).scan(paths);
    final found = {
      for (final library in libraries)
        for (final c in library.candidates) c.file,
    };
    for (final path in paths) {
      if (!found.contains(project.relative(path))) {
        throw ShutterException.noInput(
          '${project.relative(path)} has no @Preview.',
        );
      }
    }
    // Hashed before rendering, so the record is the file that was shot.
    final shellRecord = shell == null ? null : shellFile(project, shell);
    final runDir = createTimestampDir(project.runsDir, context.clock());
    final engine = context.engineFactory(sdk);
    final shots = await engine.capture(
      CaptureRequest(
        project: project,
        libraries: libraries,
        runDir: runDir,
        settleMs: settle,
        widget: widget,
        shell: shell,
        actions: actions,
        screen: screen,
        viewport: viewport,
      ),
    );
    final manifest = RunManifest(
      run: p.basename(runDir),
      shots: [...shots]..sort(Shot.bySource),
      shell: shellRecord,
      actions: [for (final action in actions) action.label],
      screen: screen,
      viewport: viewport,
    )..write(runDir);
    reportShots(manifest, runDir, ShutterIO.stdoutSink);
    return manifest.exitCode;
  }
}

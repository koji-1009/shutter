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
/// `--widget`, into a new run. With [semantics], `shutter semantics`:
/// the same shots, drawn as their semantics tree.
class ShotCommand(final ShutterContext context, {final bool semantics = false})
    extends Command<int> {
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
      )
      ..addOption(
        'keyboard',
        help:
            'Lay out as with an on-screen keyboard this many logical pixels '
            'high, e.g. 336 (experimental); the keyboard is not drawn'
            '${semantics ? '' : ' (see --keyboard-tint)'}.',
      );
    // Paint only: the semantics tree has no keyboard.
    if (!semantics) {
      argParser.addOption(
        'keyboard-tint',
        help:
            'Paint the --keyboard area in this color, as RRGGBB or AARRGGBB, '
            'e.g. 9E9E9E.',
      );
    }
    argParser.addMultiOption(
      'network-image',
      help:
          'Serve this file to Image.network for this URL, as <url>=<file>, '
          'e.g. https://example.com/avatar.png=test/images/avatar.png. '
          'Repeatable.',
      splitCommas: false,
    );
  }

  @override
  String get name => semantics ? 'semantics' : 'shot';

  @override
  String get description => semantics
      ? 'Draw the semantics tree of the previews in the named files, or of '
            'one --widget, to PNG as a new run.'
      : 'Render the previews in the named files, or one --widget, to PNG as '
            'a new run.';

  @override
  String get invocation =>
      'shutter $name <preview-file>... | shutter $name --widget <expression>';

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
    final keyboard = switch (args.option('keyboard')) {
      final raw? => parseKeyboard(raw),
      null => null,
    };
    final keyboardTint = switch (semantics
        ? null
        : args.option('keyboard-tint')) {
      final raw? => parseKeyboardTint(raw),
      null => null,
    };
    final networkImages = parseNetworkImages(
      args.multiOption('network-image'),
      workingDirectory: context.workingDirectory,
    );
    final files = args.rest;
    if (source == null && (imports.isNotEmpty || size != null)) {
      throw ShutterException.usage('--import and --size need --widget.');
    }
    if (keyboardTint != null && keyboard == null) {
      throw ShutterException.usage('--keyboard-tint needs --keyboard.');
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
    requireFlutterTest(project);
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
    final shellRecord = shell == null ? null : recordedFile(project, shell);
    final imageRecords = networkImageFiles(project, networkImages);
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
        keyboard: keyboard,
        keyboardTint: keyboardTint,
        networkImages: networkImages,
        semantics: semantics,
      ),
    );
    final manifest = RunManifest(
      run: p.basename(runDir),
      shots: [...shots]..sort(Shot.bySource),
      shell: shellRecord,
      setup: (
        actions: [for (final action in actions) action.label],
        screen: screen,
        viewport: viewport,
        keyboard: keyboard,
        keyboardTint: keyboardTint,
        networkImages: imageRecords,
        semantics: semantics,
      ),
    )..write(runDir);
    reportShots(manifest, runDir, ShutterIO.stdoutSink);
    return manifest.exitCode;
  }
}

import 'package:args/command_runner.dart';

import '../api/shoot.dart';
import '../reporters/shot_reporter.dart';
import '../run/manifest.dart';
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
        help:
            'Logical size of the --widget shot, e.g. 390x844, or '
            '$unboundedSize to shoot it at its own size with neither '
            'dimension bounded.',
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
    argParser
      ..addMultiOption(
        'network-image',
        help:
            'Serve this file to Image.network for this URL, as <url>=<file>, '
            'e.g. https://example.com/avatar.png=test/images/avatar.png. '
            'Repeatable.',
        splitCommas: false,
      )
      ..addOption(
        'platform',
        help:
            'Draw the app as on this platform: its theme, page transitions, '
            'and adaptive widgets.',
        allowed: [for (final platform in ShotPlatform.values) platform.name],
        defaultsTo: ShotPlatform.android.name,
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
    final rawSize = args.option('size');
    final unbounded = rawSize == unboundedSize;
    final size = switch (rawSize) {
      final raw? when !unbounded => parseSize(raw),
      _ => null,
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
    final networkImages = parseNetworkImages(args.multiOption('network-image'));
    final platform = ShotPlatform.values.byName(args.option('platform')!);
    final files = args.rest;
    if (source == null && (imports.isNotEmpty || rawSize != null)) {
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
    final (:dir, :manifest) = await shoot(
      context,
      ShotPlan(
        files: files,
        widget: switch (source) {
          final source? => (
            source: source,
            imports: imports,
            size: size,
            unbounded: unbounded,
          ),
          null => null,
        },
        settleMs: settle,
        shell: args.option('shell'),
        actions: actions,
        screen: screen,
        viewport: viewport,
        keyboard: keyboard,
        keyboardTint: keyboardTint,
        networkImages: networkImages,
        semantics: semantics,
        platform: platform,
      ),
    );
    reportShots(manifest, dir, ShutterIO.stdoutSink);
    return manifest.exitCode;
  }
}

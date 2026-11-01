import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../engine/interaction.dart';
import '../engine/widget_shot.dart';
import '../project/project.dart';
import '../run/manifest.dart';
import '../shutter_exception.dart';

/// The `--size` that lays the `--widget` out with neither dimension
/// bounded.
const unboundedSize = 'unbounded';

/// The `--widget` expression with its `--import` files resolved to URIs:
/// `package:flutter/widgets.dart` first, then each import.
WidgetShot parseWidgetShot(
  Project project, {
  required String source,
  required List<String> imports,
  required (double, double)? size,
  required bool unbounded,
  required String workingDirectory,
}) => WidgetShot(
  source: source,
  imports: [
    'package:flutter/widgets.dart',
    for (final import in imports) _importUri(project, import, workingDirectory),
  ],
  size: size,
  unbounded: unbounded,
);

/// Parses option [name] as an integer ≥ 0, or throws a usage error.
int parseCount(ArgResults results, String name) {
  final raw = results.option(name)!;
  final value = int.tryParse(raw);
  if (value == null || value < 0) {
    throw ShutterException.usage(
      '--$name must be a whole number ≥ 0 (got "$raw").',
    );
  }
  return value;
}

/// Parses option [name] (`--size`, `--viewport`) as `<width>x<height>`
/// in logical pixels.
(double, double) parseSize(String raw, {String name = 'size'}) {
  final parts = raw.split('x');
  final values = [for (final part in parts) double.tryParse(part)];
  if (values case [final width?, final height?]
      when width > 0 && height > 0 && width.isFinite && height.isFinite) {
    return (width, height);
  }
  final unbounded = name == 'size' ? ', or $unboundedSize' : '';
  throw ShutterException.usage(
    '--$name must be <width>x<height>, e.g. 390x844$unbounded (got "$raw").',
  );
}

/// Parses `--keyboard` as a height in logical pixels.
double parseKeyboard(String raw) {
  final height = double.tryParse(raw);
  if (height != null && height > 0 && height.isFinite) return height;
  throw ShutterException.usage(
    '--keyboard must be a height in logical pixels, e.g. 336 (got "$raw").',
  );
}

final _hexColor = RegExp(r'^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');

/// Parses `--keyboard-tint` as `RRGGBB` or `AARRGGBB`, `#` optional, into
/// ARGB; six digits are opaque.
int parseKeyboardTint(String raw) {
  final match = _hexColor.firstMatch(raw);
  if (match == null) {
    throw ShutterException.usage(
      '--keyboard-tint must be a color as RRGGBB or AARRGGBB, e.g. 9E9E9E '
      '(got "$raw").',
    );
  }
  final digits = match.group(1)!;
  return int.parse(digits.length == 6 ? 'FF$digits' : digits, radix: 16);
}

/// Splits each `--network-image <url>=<file>` into the file for its URL,
/// in the order given. The URL ends at the last `=`, so its query keeps
/// its own; [resolveNetworkImages] checks both.
Map<String, String> parseNetworkImages(List<String> raws) {
  final images = <String, String>{};
  for (final raw in raws) {
    final equals = raw.lastIndexOf('=');
    if (equals < 0) throw _networkImageUsage(raw);
    final key = raw.substring(0, equals);
    if (images.containsKey(key)) {
      throw ShutterException.usage('--network-image gives $key twice.');
    }
    images[key] = raw.substring(equals + 1);
  }
  return images;
}

/// The usage error of a `--network-image` given as [raw].
ShutterException _networkImageUsage(String raw) => ShutterException.usage(
  '--network-image must be <url>=<file>, e.g. '
  'https://example.com/avatar.png=test/images/avatar.png (got "$raw").',
);

/// The absolute path of the file served for each `http` or `https` URL
/// of [images], in its order. Each file is relative to
/// [workingDirectory] and must exist.
Map<String, String> resolveNetworkImages(
  Map<String, String> images, {
  required String workingDirectory,
}) => {
  for (final MapEntry(key: raw, value: file) in images.entries)
    raw: _networkImageFile(raw, file, workingDirectory),
};

String _networkImageFile(String raw, String file, String workingDirectory) {
  final url = Uri.tryParse(raw);
  if (url == null ||
      !(url.isScheme('http') || url.isScheme('https')) ||
      url.host.isEmpty ||
      file.isEmpty) {
    throw _networkImageUsage('$raw=$file');
  }
  final path = p.normalize(p.join(workingDirectory, file));
  if (!File(path).existsSync()) {
    throw ShutterException.noInput(
      '--network-image file $file does not exist.',
    );
  }
  return path;
}

/// The manifest record of each `--network-image` file in [images].
Map<String, RecordedFile> networkImageFiles(
  Project project,
  Map<String, String> images,
) => {
  for (final MapEntry(:key, :value) in images.entries)
    key: recordedFile(project, value),
};

/// The actions of `shot`: every `--tap` and `--enter` in the order given,
/// then the one `--press`, `--hover`, or `--focus`, whose state lasts
/// through the capture.
List<ShotAction> parseActions(ArgResults results) {
  final held = [
    for (final kind in const [
      ActionKind.press,
      ActionKind.hover,
      ActionKind.focus,
    ])
      for (final raw in results.multiOption(kind.name)) (kind, raw),
  ];
  if (held.length > 1) {
    throw ShutterException.usage(
      'Give at most one of --press, --hover, and --focus.',
    );
  }
  // The parser keeps each option's values in order, but not the order
  // between options, which the command line still has.
  final steps = {
    for (final kind in const [ActionKind.tap, ActionKind.enter])
      kind: [...results.multiOption(kind.name)],
  };
  return [
    for (final argument in results.arguments.takeWhile((a) => a != '--'))
      for (final MapEntry(key: kind, value: values) in steps.entries)
        if ((argument == '--${kind.name}' ||
                argument.startsWith('--${kind.name}=')) &&
            values.isNotEmpty)
          _action(kind, values.removeAt(0)),
    for (final (kind, raw) in held) _action(kind, raw),
  ];
}

ShotAction _action(ActionKind kind, String raw) {
  var target = raw;
  String? text;
  if (kind == ActionKind.enter) {
    final equals = raw.indexOf('=');
    if (equals < 0) {
      throw ShutterException.usage(
        '--enter must be <target>=<text>, e.g. key:name=Koji (got "$raw").',
      );
    }
    (target, text) = (raw.substring(0, equals), raw.substring(equals + 1));
  }
  final colon = target.indexOf(':');
  final by = colon < 0
      ? null
      : TargetKind.values.asNameMap()[target.substring(0, colon)];
  final value = target.substring(colon + 1);
  if (by == null || value.isEmpty) {
    throw ShutterException.usage(
      '--${kind.name} must name its widget by key:<key>, text:<text>, '
      'label:<label>, or type:<Widget> (got "$raw").',
    );
  }
  final shotTarget = ShotTarget(by, value);
  return switch (kind) {
    ActionKind.tap => ShotAction.tap(shotTarget),
    ActionKind.enter => ShotAction.enter(shotTarget, text!),
    ActionKind.press => ShotAction.press(shotTarget),
    ActionKind.hover => ShotAction.hover(shotTarget),
    ActionKind.focus => ShotAction.focus(shotTarget),
  };
}

/// Help of the target the action options take.
const targetHelp =
    'key:<ValueKey<String>>, text:<Text data>, label:<semantics label>, or '
    'type:<Widget>';

String _importUri(Project project, String import, String workingDirectory) =>
    import.startsWith('package:')
    ? import
    : project.packageUri(
        libFile(
          project,
          import,
          workingDirectory: workingDirectory,
          what: '--import',
        ),
      );

/// Help of the `--shell` option of `shot`, `init`, and `doctor`.
const shellHelp =
    'Shell file to use instead of <preview dir>/shell.dart; any path, '
    'e.g. .dart_tool/shutter/shell.dart.';

/// Absolute path of the `--shell` [option], relative to
/// [workingDirectory].
String shellOptionPath(String option, String workingDirectory) =>
    p.normalize(p.join(workingDirectory, option));

/// The shell file `shot` uses: the `--shell` [option], which must exist,
/// else `<preview dir>/shell.dart` when present, else null.
String? resolveShell(
  Project project,
  String? option, {
  required String workingDirectory,
}) {
  if (option == null) return project.shellPath;
  final path = shellOptionPath(option, workingDirectory);
  if (!File(path).existsSync()) {
    throw ShutterException.noInput('--shell $option does not exist.');
  }
  return path;
}

/// The manifest record of the file at [path], such as the shell file.
RecordedFile recordedFile(Project project, String path) => (
  path: project.shown(path),
  sha256: sha256.convert(File(path).readAsBytesSync()).toString(),
);

/// Absolute path of [path], relative to [workingDirectory], which must be
/// a file under `lib/`. [what] names it in errors.
String libFile(
  Project project,
  String path, {
  required String workingDirectory,
  required String what,
}) {
  final resolved = p.normalize(p.join(workingDirectory, path));
  if (!File(resolved).existsSync()) {
    throw ShutterException.noInput('$what $path does not exist.');
  }
  if (!p.isWithin(project.libDir, resolved)) {
    throw ShutterException.usage('$what must be under lib/ ($path).');
  }
  return resolved;
}

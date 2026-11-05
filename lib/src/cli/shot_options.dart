import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../api/shot.dart';
import '../engine/interaction.dart';
import '../shutter_exception.dart';

/// The `--size` that lays the `--widget` out with neither dimension
/// bounded.
const unboundedSize = 'unbounded';

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

/// Parses `--viewport` as `<width>x<height>` in logical pixels; `shoot`
/// checks the size.
LogicalSize parseViewport(String raw) {
  if (_dimensions(raw) case (final width, final height?)) {
    return LogicalSize(width, height);
  }
  throw ShutterException.usage(
    '--viewport must be <width>x<height>, e.g. 390x844 (got "$raw").',
  );
}

/// Parses `--size`: `<width>x<height>` in logical pixels, `<width>x` for
/// a width with the height left unbounded, or [unboundedSize]; `shoot`
/// checks the size.
WidgetSize parseWidgetSize(String raw) {
  if (raw == unboundedSize) return WidgetSize.unbounded;
  return switch (_dimensions(raw)) {
    (final width, final height?) => LogicalSize(width, height),
    (final width, null) => LogicalSize(width, double.infinity),
    null => throw ShutterException.usage(
      '--size must be <width>x<height>, <width>x for its own height, or '
      '$unboundedSize, e.g. 390x844 or 390x (got "$raw").',
    ),
  };
}

/// The width and height of `<width>x<height>`, or the width alone of
/// `<width>x`; null for anything else.
(double, double?)? _dimensions(String raw) {
  final parts = raw.split('x');
  if (parts.length != 2) return null;
  final width = double.tryParse(parts[0]);
  if (width == null) return null;
  if (parts[1].isEmpty) return (width, null);
  return switch (double.tryParse(parts[1])) {
    final height? => (width, height),
    null => null,
  };
}

/// Parses `--keyboard` as a height in logical pixels; `shoot` checks the
/// height.
double parseKeyboard(String raw) {
  if (double.tryParse(raw) case final height?) return height;
  throw ShutterException.usage(
    '--keyboard must be a height in logical pixels, e.g. 336 (got "$raw").',
  );
}

/// Parses `--pixel-ratio` as a number; `shoot` checks the ratio.
double parsePixelRatio(String raw) {
  if (double.tryParse(raw) case final ratio?) return ratio;
  throw ShutterException.usage(
    '--pixel-ratio must be a number, e.g. 3 (got "$raw").',
  );
}

/// Parses `--text-scale` as a number; `shoot` checks the scale.
double parseTextScale(String raw) {
  if (double.tryParse(raw) case final scale?) return scale;
  throw ShutterException.usage(
    '--text-scale must be a number, e.g. 1.3 (got "$raw").',
  );
}

/// Parses `--safe-area` as `<top>,<bottom>` in logical pixels; `shoot`
/// checks the insets.
SafeAreaInsets parseSafeArea(String raw) {
  final values = [for (final part in raw.split(',')) double.tryParse(part)];
  if (values case [final top?, final bottom?]) {
    return SafeAreaInsets(top: top, bottom: bottom);
  }
  throw ShutterException.usage(
    '--safe-area must be <top>,<bottom> in logical pixels, e.g. 59,34 '
    '(got "$raw").',
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
/// its own; `shoot` checks both.
Map<String, String> parseNetworkImages(List<String> raws) {
  final images = <String, String>{};
  for (final raw in raws) {
    final equals = raw.lastIndexOf('=');
    if (equals < 0) {
      throw ShutterException.usage(
        '--network-image must be <url>=<file>, e.g. '
        'https://example.com/avatar.png=test/images/avatar.png (got "$raw").',
      );
    }
    final key = raw.substring(0, equals);
    if (images.containsKey(key)) {
      throw ShutterException.usage('--network-image gives $key twice.');
    }
    images[key] = raw.substring(equals + 1);
  }
  return images;
}

/// The actions of `shot`: every `--tap` and `--enter` in the order given,
/// then each `--press`, `--hover`, and `--focus`, whose state lasts
/// through the capture; `shoot` takes at most one of those.
List<ShotAction> parseActions(ArgResults results) {
  final held = [
    for (final kind in ActionKind.values.where((kind) => kind.held))
      for (final raw in results.multiOption(kind.name)) (kind, raw),
  ];
  // The parser keeps each option's values in order, but not the order
  // between options, which the command line still has.
  final steps = {
    for (final kind in ActionKind.values.where((kind) => !kind.held))
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
  if (by == null) {
    throw ShutterException.usage(
      '--${kind.name} must name its widget by key:<key>, text:<text>, '
      'label:<label>, or type:<Widget> (got "$raw").',
    );
  }
  final shotTarget = ShotTarget(by, target.substring(colon + 1));
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

/// Help of the `--shell` option of `shot`, `init`, and `doctor`.
const shellHelp =
    'Shell file to use instead of <preview dir>/shell.dart; any path, '
    'e.g. .dart_tool/shutter/shell.dart.';

/// Absolute path of the `--shell` [option], relative to
/// [workingDirectory].
String shellOptionPath(String option, String workingDirectory) =>
    p.normalize(p.join(workingDirectory, option));

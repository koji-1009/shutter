import '../dart_literal.dart';

/// What an action does to its target before the capture.
enum ActionKind {
  /// Taps it: a pointer down and up.
  tap,

  /// Enters text into it, as a keyboard would.
  enter,

  /// Holds a pointer down on it through the capture.
  press,

  /// Keeps a mouse pointer over it through the capture.
  hover,

  /// Gives it keyboard focus, with the focus highlight a keyboard shows.
  focus,
}

/// How an action's target is found.
enum TargetKind {
  /// A `ValueKey<String>`.
  key,

  /// A `Text` showing exactly this string, or an `EditableText` holding it.
  text,

  /// A widget by its type name, with or without type arguments.
  type,

  /// A widget whose semantics label is exactly this string: a text
  /// field's label or hint, a button's text.
  label,
}

/// One `shot --tap`, `--enter`, `--press`, `--hover`, or `--focus`.
class const ShotAction({
  required final ActionKind kind,
  required final TargetKind by,

  /// The key, text, or type name.
  required final String value,

  /// The text `--enter` types.
  final String? text,
}) {
  /// As given on the command line, and recorded in the manifest:
  /// `tap text:Save`, `enter key:name=Koji`.
  String get label => switch (text) {
    final text? => '${kind.name} ${by.name}:$value=$text',
    null => '${kind.name} ${by.name}:$value',
  };

  /// The harness's `ShutterAction` for this action, as Dart source.
  String get source => switch (text) {
    final text? =>
      '\$shutter.ShutterAction(.${kind.name}, .${by.name}, '
          '${dartString(value)}, text: ${dartString(text)})',
    null =>
      '\$shutter.ShutterAction(.${kind.name}, .${by.name}, '
          '${dartString(value)})',
  };
}

import '../dart_literal.dart';

/// What an action does to its target before the capture.
enum ActionKind {
  /// Taps it: a pointer down and up.
  tap,

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
}

/// One `shot --tap`, `--press`, `--hover`, or `--focus`.
class const ShotAction({
  required final ActionKind kind,
  required final TargetKind by,

  /// The key, text, or type name.
  required final String value,
}) {
  /// As given on the command line, and recorded in the manifest:
  /// `tap text:Save`.
  String get label => '${kind.name} ${by.name}:$value';

  /// The harness's `ShutterAction` for this action, as Dart source.
  String get source =>
      '\$shutter.ShutterAction(.${kind.name}, .${by.name}, '
      '${dartString(value)})';
}

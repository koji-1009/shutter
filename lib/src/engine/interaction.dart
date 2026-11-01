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

/// The widget an action acts on: `key:<value>`, `text:<value>`,
/// `label:<value>`, or `type:<value>` on the command line.
class const ShotTarget(
  /// How the widget is found.
  final TargetKind by,

  /// The key, text, label, or type name.
  final String value,
) {
  /// The widget with a `ValueKey<String>` of [value].
  const ShotTarget.key(String value) : this(TargetKind.key, value);

  /// The `Text` showing exactly [value], or the `EditableText` holding it.
  const ShotTarget.text(String value) : this(TargetKind.text, value);

  /// The widget whose semantics label is exactly [value]: a text field's
  /// label or hint, a button's text.
  const ShotTarget.label(String value) : this(TargetKind.label, value);

  /// The widget of type [value], with or without type arguments, e.g.
  /// `DropdownButton<String>`.
  const ShotTarget.type(String value) : this(TargetKind.type, value);
}

/// One `shot --tap`, `--enter`, `--press`, `--hover`, or `--focus`.
class const ShotAction._(
  final ActionKind kind,

  /// The widget it acts on.
  final ShotTarget target, [

  /// The text `--enter` types.
  final String? text,
]) {
  /// Taps [target]: a pointer down and up.
  const ShotAction.tap(ShotTarget target) : this._(ActionKind.tap, target);

  /// Enters [text] into the text field [target] is or holds, as a
  /// keyboard would.
  const ShotAction.enter(ShotTarget target, String text)
    : this._(ActionKind.enter, target, text);

  /// Holds a pointer down on [target] through the capture.
  const ShotAction.press(ShotTarget target) : this._(ActionKind.press, target);

  /// Keeps a mouse pointer over [target] through the capture.
  const ShotAction.hover(ShotTarget target) : this._(ActionKind.hover, target);

  /// Gives [target] keyboard focus, highlighted as with a keyboard.
  const ShotAction.focus(ShotTarget target) : this._(ActionKind.focus, target);

  /// How [target] is found.
  TargetKind get by => target.by;

  /// The key, text, label, or type name of [target].
  String get value => target.value;

  /// Whether the state it leaves lasts through the capture: a press, a
  /// hover, or focus.
  bool get held => switch (kind) {
    ActionKind.tap || ActionKind.enter => false,
    ActionKind.press || ActionKind.hover || ActionKind.focus => true,
  };

  /// As given on the command line, and recorded in the manifest:
  /// `tap text:Save`, `enter key:name=Koji`.
  String get label {
    final text = switch (this.text) {
      final text? => '=$text',
      null => '',
    };
    return '${kind.name} ${by.name}:$value$text';
  }
}

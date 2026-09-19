import '../dart_literal.dart';
import '../scan/candidate.dart';
import 'generator.dart';

/// A widget given with `shot --widget`, shot on its own without a
/// preview file.
class const WidgetShot({
  /// Dart expression of type `Widget`.
  required final String source,

  /// URIs the widget expression needs imported,
  /// `package:flutter/widgets.dart` first.
  required final List<String> imports,

  /// Logical size, when given.
  final (double, double)? size,
}) {
  /// Static half of the shot id: the expression and its imports, so the
  /// same `--widget` and `--import` give the same id in every run.
  String get staticId => shortHash([source, ...imports].join('|'));

  /// Source of the helper library shooting this widget: its imports,
  /// unprefixed as the expression expects, and `entries()`.
  String helperSource() {
    final size = switch (this.size) {
      (final width, final height) => ', size: \$ui.Size($width, $height)',
      null => '',
    };
    return helperLibrary(
      source: '--widget',
      imports: [
        for (final uri in imports) "import '$uri';",
        r"import 'dart:ui' as $ui;",
        r"import 'package:flutter/widget_previews.dart' as $preview;",
      ],
      entries: [
        {
          'id': "'$staticId'",
          'annotation':
              '() => const \$preview.Preview(name: ${dartString(source)}$size)',
          'target': '() => $source',
        },
      ],
    );
  }
}

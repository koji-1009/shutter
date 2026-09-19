import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../ui/tag_row.dart';

/// A theme applied through `@Preview(theme:)`.
final class AmberChips extends PreviewThemeData {
  const AmberChips();

  @override
  Widget apply(BuildContext context, Widget child) => Theme(
    data: Theme.of(
      context,
    ).copyWith(chipTheme: const ChipThemeData(backgroundColor: Colors.amber)),
    child: child,
  );
}

PreviewThemeData cardTheme() => const AmberChips();

class TagRowPreviews {
  static Widget padded(Widget child) =>
      Padding(padding: const EdgeInsets.all(8), child: child);

  /// Fits: sized by its content, no explicit size.
  @Preview(name: 'TagRow / fits', wrapper: padded, theme: cardTheme)
  static Widget fits() => const TagRow(tags: ['new', 'sale']);

  /// Overflows on purpose: an `error` shot with a location.
  @Preview(name: 'TagRow / overflow', size: Size(200, 48))
  static Widget overflow() =>
      const TagRow(tags: ['limited edition', 'free shipping', 'bestseller']);

  /// A `WidgetBuilder` preview with a text scale factor.
  @Preview(
    name: 'TagRow / large text',
    size: Size(360, 64),
    textScaleFactor: 1.5,
  )
  static WidgetBuilder largeText() =>
      (context) => const TagRow(tags: ['new', 'sale']);
}

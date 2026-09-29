import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'pixel_diff.dart';

/// How the three panels of a composite are laid out.
enum CompositeDirection {
  /// Side by side for a portrait panel, stacked for a landscape one.
  auto,

  /// `before | diff | after`, side by side.
  horizontal,

  /// `before`, `diff`, `after`, stacked.
  vertical,
}

/// The neutral grey the sheet shows around and between the panels, and
/// where only one side of a shot covers the union canvas.
const _background = 0x9E;

/// Caption text, and the rectangle marking a source image's own bounds.
final _ink = img.ColorRgb8(0x1A, 0x1A, 0x1A);

/// Geometry of one composite sheet, in physical pixels. Every length is
/// derived from the panel, so the chrome keeps its share of the sheet
/// whatever the subject's size.
class CompositeLayout {
  CompositeLayout(
    this.panel, {
    this.direction = CompositeDirection.auto,
    this.titleHeight = 0,
  });

  /// Size of one panel: the union canvas of the two shots.
  final (int, int) panel;
  final CompositeDirection direction;

  /// Height of the title image above the panels, 0 without one.
  final int titleHeight;

  /// Side by side, rather than stacked.
  bool get horizontal => switch (direction) {
    CompositeDirection.horizontal => true,
    CompositeDirection.vertical => false,
    // Side by side keeps all three panels in one view, which is what a
    // composite is for; stacking a portrait panel puts before and after a
    // screenful apart.
    CompositeDirection.auto => panel.$2 >= panel.$1,
  };

  int get gutter => (panel.$1 ~/ 24).clamp(16, 48);

  /// Caption font. The captions are ASCII, which every bundled font
  /// covers; the larger one keeps them legible on a sheet a viewer scales
  /// down.
  img.BitmapFont get font => panel.$1 >= 400 ? img.arial48 : img.arial24;

  /// Height of a caption band.
  int get band => font.lineHeight + gutter;

  /// The largest bundled font [caption] fits a band in, down to the
  /// smallest there is. The band keeps the height [font] gives it.
  img.BitmapFont captionFont(String caption) {
    for (final candidate in [font, img.arial24, img.arial14]) {
      if (_fits(caption, candidate)) return candidate;
    }
    return img.arial14;
  }

  /// The first of [captions] that fits a band even at the smallest font,
  /// else the last: a caption too long for its panel is said shorter
  /// rather than cut off at the sheet's edge, or over its neighbour.
  String fittingCaption(List<String> captions) {
    for (final caption in captions) {
      if (_fits(caption, img.arial14)) return caption;
    }
    return captions.last;
  }

  /// Whether [caption] drawn in [font] stays within its panel and the one
  /// gutter beside it, which is all the room a caption has.
  bool _fits(String caption, img.BitmapFont font) {
    var width = 0;
    for (final unit in caption.codeUnits) {
      width += font.characters[unit]?.xAdvance ?? font.base ~/ 2;
    }
    return width <= panel.$1 + gutter;
  }

  /// Where the panels start, below the title.
  int get top => titleHeight == 0 ? 0 : gutter + titleHeight;

  int get width =>
      horizontal ? 3 * panel.$1 + 4 * gutter : panel.$1 + 2 * gutter;

  /// Width a title has between the gutters, and the size the caption
  /// bands are set in: every sheet with the same pair takes the same
  /// title image. A caption that does not fit its panel is drawn smaller
  /// than this; the title, which has the whole sheet, is not.
  (int, int) get title => (width - 2 * gutter, font.base);

  int get height =>
      top +
      (horizontal
          ? band + panel.$2 + 2 * gutter
          : 3 * (band + panel.$2) + 4 * gutter);

  /// Top left of panel [index] — 0 before, 1 diff, 2 after.
  (int, int) origin(int index) => horizontal
      ? (gutter + index * (panel.$1 + gutter), top + gutter + band)
      : (gutter, top + gutter + index * (band + panel.$2 + gutter) + band);
}

/// Draws one sheet: [before], [diff] and [after] on the union canvas, each
/// under its caption, with [title] above them.
///
/// A null [before] or [after] is a shot that has no image on that side; its
/// panel is left as background, as are the pixels a smaller shot does not
/// cover. Both are drawn over white, because a preview paints no surface of
/// its own inside the captured boundary.
img.Image compositeDiff({
  required Rgba? before,
  required img.Image diff,
  required Rgba? after,
  required CompositeLayout layout,
  required (String, String, String) captions,
  img.Image? title,
}) {
  final (panelWidth, panelHeight) = layout.panel;
  final stride = layout.width * 4;
  final out = Uint8List(layout.width * layout.height * 4);
  for (var o = 0; o < out.length; o += 4) {
    out
      ..[o] = _background
      ..[o + 1] = _background
      ..[o + 2] = _background
      ..[o + 3] = 255;
  }

  final sources = [
    before,
    Rgba(diff.width, diff.height, diff.getBytes(order: img.ChannelOrder.rgba)),
    after,
  ];
  for (final (index, source) in sources.indexed) {
    if (source == null) continue;
    final (x0, y0) = layout.origin(index);
    for (var y = 0; y < panelHeight && y < source.height; y++) {
      for (var x = 0; x < panelWidth && x < source.width; x++) {
        final o = (y0 + y) * stride + (x0 + x) * 4;
        final s = (y * source.width + x) * 4;
        final alpha = source.bytes[s + 3] / 255;
        for (var c = 0; c < 3; c++) {
          out[o + c] = (source.bytes[s + c] * alpha + 255 * (1 - alpha))
              .round();
        }
        out[o + 3] = 255;
      }
    }
  }

  final sheet = img.Image.fromBytes(
    width: layout.width,
    height: layout.height,
    bytes: out.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  // A shot smaller than the union canvas: mark where its own image ends,
  // so the background is not read as content.
  for (final (index, source) in sources.indexed) {
    if (source == null ||
        (source.width == panelWidth && source.height == panelHeight)) {
      continue;
    }
    final (x0, y0) = layout.origin(index);
    img.drawRect(
      sheet,
      x1: x0,
      y1: y0,
      x2: x0 + source.width - 1,
      y2: y0 + source.height - 1,
      color: _ink,
      thickness: 2,
    );
  }
  for (final (index, caption) in [
    captions.$1,
    captions.$2,
    captions.$3,
  ].indexed) {
    final (x0, y0) = layout.origin(index);
    final font = layout.captionFont(caption);
    img.drawString(
      sheet,
      caption,
      font: font,
      x: x0,
      y: y0 - font.lineHeight - layout.gutter ~/ 2,
      color: _ink,
    );
  }
  if (title != null) {
    img.compositeImage(sheet, title, dstX: layout.gutter, dstY: layout.gutter);
  }
  return sheet;
}

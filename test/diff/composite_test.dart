import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:shutter/src/diff/composite.dart';
import 'package:shutter/src/diff/pixel_diff.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('auto lays a portrait panel out side by side and a landscape one '
      'stacked; the tie goes side by side', () {
    for (final (panel, horizontal) in [
      ((10, 20), true),
      ((20, 10), false),
      ((20, 20), true),
    ]) {
      expect(CompositeLayout(panel).horizontal, horizontal, reason: '$panel');
    }
    expect(
      CompositeLayout((
        10,
        20,
      ), direction: CompositeDirection.vertical).horizontal,
      isFalse,
    );
    expect(
      CompositeLayout((
        20,
        10,
      ), direction: CompositeDirection.horizontal).horizontal,
      isTrue,
    );
  });

  test('the chrome keeps its share of the panel', () {
    final small = CompositeLayout((100, 200));
    expect((small.gutter, small.font.lineHeight), (16, img.arial24.lineHeight));
    final large = CompositeLayout((780, 1688));
    expect((large.gutter, large.font.lineHeight), (32, img.arial48.lineHeight));
    // Clamped at both ends, so no sheet is all chrome or all panel.
    expect(CompositeLayout((2400, 2400)).gutter, 48);
  });

  test('a caption too long for its panel steps down a font size', () {
    final wide = CompositeLayout((800, 100));
    expect(wide.captionFont('diff 31.27%, 5814px'), img.arial48);
    final narrow = CompositeLayout((166, 112));
    expect(narrow.captionFont('before'), img.arial24);
    expect(narrow.captionFont('diff 31.27%, 5814px'), img.arial14);
    // Nothing smaller to step down to.
    expect(CompositeLayout((4, 4)).captionFont('diff 100%, 16px'), img.arial14);
  });

  test('a caption that does not fit the smallest font is said shorter', () {
    // An icon-sized subject: 112px of room for the diff caption.
    final small = CompositeLayout((96, 96));
    expect(
      small.fittingCaption(['diff 100.0%, 9216px', 'diff 9216px', 'diff']),
      'diff 9216px',
    );
    expect(
      small.fittingCaption(['diff 100.0%, 9216px']),
      'diff 100.0%, 9216px',
    );
    expect(
      CompositeLayout((8, 8)).fittingCaption(['diff 9216px', 'diff']),
      'diff',
    );
    // Room to say it in full.
    final room = CompositeLayout((800, 100));
    expect(
      room.fittingCaption(['diff 100.0%, 9216px', 'diff']),
      'diff 100.0%, 9216px',
    );
  });

  test('the sheet holds three panels, the gutters, and the caption bands', () {
    final layout = CompositeLayout((60, 120));
    final (g, band) = (layout.gutter, layout.band);
    expect(layout.width, 3 * 60 + 4 * g);
    expect(layout.height, band + 120 + 2 * g);
    expect(layout.origin(0), (g, band + g));
    expect(layout.origin(1), (2 * g + 60, band + g));
    expect(layout.origin(2), (3 * g + 120, band + g));

    final stacked = CompositeLayout((120, 60));
    final (sg, sband) = (stacked.gutter, stacked.band);
    expect(stacked.width, 120 + 2 * sg);
    expect(stacked.height, 3 * (sband + 60) + 4 * sg);
    expect(stacked.origin(0), (sg, sband + sg));
    expect(stacked.origin(2), (sg, 3 * sband + 120 + 3 * sg));
  });

  test('a title raises the panels and is drawn over the background', () {
    final title = img.Image(width: 40, height: 10, numChannels: 4);
    img.fill(title, color: img.ColorRgba8(0, 0, 255, 255));
    final layout = CompositeLayout((60, 120), titleHeight: title.height);
    final plain = CompositeLayout((60, 120));
    expect(layout.top, layout.gutter + 10);
    expect(layout.height, plain.height + layout.gutter + 10);
    expect(layout.width, plain.width);
    final sheet = compositeDiff(
      before: Rgba.decode(png(60, 120)),
      diff: img.Image(width: 60, height: 120, numChannels: 4),
      after: Rgba.decode(png(60, 120)),
      layout: layout,
      captions: ('before', 'diff', 'after'),
      title: title,
    );
    final drawn = sheet.getPixel(layout.gutter, layout.gutter);
    expect([drawn.r, drawn.g, drawn.b], [0, 0, 255]);
  });

  test('panels are drawn over white; an absent side stays background', () {
    // Half transparent white over white is still white; over the sheet's
    // grey it would not be.
    final layout = CompositeLayout((4, 2));
    final sheet = compositeDiff(
      before: Rgba.decode(png(4, 2, [255, 255, 255, 128])),
      diff: img.Image(width: 4, height: 2, numChannels: 4),
      after: null,
      layout: layout,
      captions: ('before 4x2', 'diff', 'after none'),
      title: null,
    );
    final (x0, y0) = layout.origin(0);
    final covered = sheet.getPixel(x0, y0);
    expect([covered.r, covered.g, covered.b], [255, 255, 255]);
    final (x2, y2) = layout.origin(2);
    final absent = sheet.getPixel(x2, y2);
    expect([absent.r, absent.g, absent.b], [0x9E, 0x9E, 0x9E]);
  });

  test('a shot smaller than the panel is marked at its own bounds', () {
    final layout = CompositeLayout((4, 4));
    final sheet = compositeDiff(
      before: Rgba.decode(png(2, 2, [255, 255, 255, 255])),
      diff: img.Image(width: 4, height: 4, numChannels: 4),
      after: Rgba.decode(png(4, 4, [255, 255, 255, 255])),
      layout: layout,
      captions: ('before 2x2', 'diff', 'after 4x4'),
      title: null,
    );
    final (x0, y0) = layout.origin(0);
    final edge = sheet.getPixel(x0 + 1, y0 + 1);
    expect([edge.r, edge.g, edge.b], [0x1A, 0x1A, 0x1A]);
    // Outside its bounds, the panel is background rather than content.
    final uncovered = sheet.getPixel(x0 + 3, y0 + 3);
    expect([uncovered.r, uncovered.g, uncovered.b], [0x9E, 0x9E, 0x9E]);
    // The panel that fills its canvas is left alone.
    final (x2, y2) = layout.origin(2);
    final full = sheet.getPixel(x2 + 3, y2 + 3);
    expect([full.r, full.g, full.b], [255, 255, 255]);
  });

  test('captions are drawn in the band above their panel', () {
    final layout = CompositeLayout((400, 40));
    final sheet = compositeDiff(
      before: Rgba.decode(png(400, 40)),
      diff: img.Image(width: 400, height: 40, numChannels: 4),
      after: Rgba.decode(png(400, 40)),
      layout: layout,
      captions: ('before', 'diff 100%, 4px', 'after'),
      title: null,
    );
    // Ink somewhere in the first band, none in the panel's own last row.
    var inked = 0;
    final (x0, y0) = layout.origin(0);
    for (var y = y0 - layout.band; y < y0; y++) {
      for (var x = x0; x < x0 + 400; x++) {
        final pixel = sheet.getPixel(x, y);
        if (pixel.r == 0x1A && pixel.g == 0x1A && pixel.b == 0x1A) inked++;
      }
    }
    expect(inked, greaterThan(0));
  });

  test('an absent side leaves its panel empty', () {
    final layout = CompositeLayout((2, 2));
    final sheet = compositeDiff(
      before: null,
      diff: img.Image(width: 2, height: 2, numChannels: 4),
      after: Rgba(2, 2, Uint8List(16)),
      layout: layout,
      captions: ('before none', 'diff 100%, 4px', 'after'),
      title: null,
    );
    expect([sheet.width, sheet.height], [layout.width, layout.height]);
  });
}

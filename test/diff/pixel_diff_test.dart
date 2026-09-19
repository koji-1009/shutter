import 'dart:typed_data';

import 'package:shutter/src/diff/pixel_diff.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('decode converts to RGBA8; non-PNG bytes are rejected', () {
    final rgba = Rgba.decode(png(2, 1, [10, 20, 30, 255]));
    expect([rgba.width, rgba.height], [2, 1]);
    expect(rgba.bytes, [10, 20, 30, 255, 10, 20, 30, 255]);
    expect(() => Rgba.decode(Uint8List(4)), throwsFormatException);
  });

  test('identical images: no differences, nothing red', () {
    final a = Rgba.decode(png(3, 2, [0, 0, 0, 255]));
    final diff = comparePixels(a, a);
    expect(diff.differing, 0);
    expect(diff.ratio, 0);
    final pixel = diffImage(a, a).getPixel(0, 0);
    expect([pixel.r, pixel.g, pixel.b], isNot([255, 0, 0]));
  });

  test('differing pixels are red; a size mismatch counts the union; every '
      'channel counts', () {
    final a = Rgba.decode(png(2, 2, [0, 0, 0, 255]));
    final b = Rgba.decode(png(3, 1, [0, 0, 0, 255]));
    final diff = comparePixels(a, b);
    expect(diff.total, 6);
    expect(diff.differing, 4);
    final image = diffImage(a, b);
    expect([image.width, image.height], [3, 2]);
    final red = image.getPixel(2, 0);
    expect([red.r, red.g, red.b], [255, 0, 0]);
    final belowAfter = image.getPixel(0, 1);
    expect([belowAfter.r, belowAfter.g, belowAfter.b], [255, 0, 0]);

    final c = Rgba.decode(png(2, 2, [0, 0, 1, 255]));
    expect(comparePixels(a, c).ratio, 1);
    expect(
      comparePixels(Rgba(0, 0, Uint8List(0)), Rgba(0, 0, Uint8List(0))).ratio,
      0,
    );
    for (final other in [
      [1, 0, 0, 255],
      [0, 1, 0, 255],
      [0, 0, 0, 254],
    ]) {
      expect(comparePixels(a, Rgba.decode(png(2, 2, other))).differing, 4);
    }
  });
}

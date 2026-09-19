import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// RGBA8 pixels of a decoded PNG.
class Rgba(
  final int width,
  final int height,

  /// `width * height * 4` bytes, row-major, RGBA.
  final Uint8List bytes,
) {
  /// Decodes [png] and converts it to 8-bit RGBA.
  factory Rgba.decode(Uint8List png) {
    final image = img.decodePng(png);
    if (image == null) throw const FormatException('not a PNG');
    final rgba = image.convert(format: img.Format.uint8, numChannels: 4);
    return Rgba(
      rgba.width,
      rgba.height,
      rgba.getBytes(order: img.ChannelOrder.rgba),
    );
  }
}

/// Result of comparing two images on their union canvas.
class const PixelDiff({
  /// Pixels that differ, counting every pixel covered by only one image,
  /// so images of different sizes always differ.
  required final int differing,

  /// Pixels of the union canvas.
  required final int total,
}) {
  double get ratio => total == 0 ? 0 : differing / total;
}

/// Compares [before] and [after] pixel by pixel (exact RGBA equality).
PixelDiff comparePixels(Rgba before, Rgba after) {
  final (width, height) = _union(before, after);
  var differing = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (!_same(before, after, x, y)) differing++;
    }
  }
  return PixelDiff(differing: differing, total: width * height);
}

/// Faded grayscale of [before] on the union canvas, with the pixels that
/// differ from [after] in red.
img.Image diffImage(Rgba before, Rgba after) {
  final (width, height) = _union(before, after);
  final out = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final o = (y * width + x) * 4;
      if (_same(before, after, x, y)) {
        final b = (y * before.width + x) * 4;
        final alpha = before.bytes[b + 3] / 255;
        final luma =
            0.299 * before.bytes[b] +
            0.587 * before.bytes[b + 1] +
            0.114 * before.bytes[b + 2];
        // Blend towards white so unchanged content reads as context.
        final faded = (255 - (255 - luma * alpha - 255 * (1 - alpha)) * 0.1)
            .round();
        out
          ..[o] = faded
          ..[o + 1] = faded
          ..[o + 2] = faded;
      } else {
        out
          ..[o] = 255
          ..[o + 1] = 0
          ..[o + 2] = 0;
      }
      out[o + 3] = 255;
    }
  }
  return img.Image.fromBytes(
    width: width,
    height: height,
    bytes: out.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}

(int, int) _union(Rgba a, Rgba b) => (
  a.width > b.width ? a.width : b.width,
  a.height > b.height ? a.height : b.height,
);

/// Whether both images cover (x, y) with the same RGBA.
bool _same(Rgba before, Rgba after, int x, int y) {
  if (x >= before.width || y >= before.height) return false;
  if (x >= after.width || y >= after.height) return false;
  final b = (y * before.width + x) * 4;
  final a = (y * after.width + x) * 4;
  return before.bytes[b] == after.bytes[a] &&
      before.bytes[b + 1] == after.bytes[a + 1] &&
      before.bytes[b + 2] == after.bytes[a + 2] &&
      before.bytes[b + 3] == after.bytes[a + 3];
}

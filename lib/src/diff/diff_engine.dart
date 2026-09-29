import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../run/manifest.dart';
import '../run/run_store.dart';
import 'composite.dart';
import 'pixel_diff.dart';
import 'run_diff.dart';

/// The absent side of a one-sided entry: an image covering nothing, so the
/// union canvas is the other side's and every pixel of it differs.
final _absent = Rgba(0, 0, Uint8List(0));

/// Compares [before] and [after] by shot id. [dir] is the diff directory
/// the images go into: with [images], `<id>.png` marking the differing
/// pixels of every entry that has both of them; with [composite],
/// `<id>-composite.png` holding the before, diff and after panels of every
/// entry that has something to show, under the title [titles] holds for
/// its sheet (see [CompositeLayout.title]).
RunDiff diffRuns(
  StoredRun before,
  StoredRun after, {
  String? dir,
  bool images = false,
  CompositeDirection? composite,
  Map<(int, int), img.Image> titles = const {},
}) {
  final beforeShots = {for (final s in before.manifest.shots) s.id: s};
  final afterShots = {for (final s in after.manifest.shots) s.id: s};
  final ids = {...beforeShots.keys, ...afterShots.keys};
  final entries = [
    for (final id in ids)
      _entry(
        id,
        before,
        beforeShots[id],
        after,
        afterShots[id],
        dir: dir,
        images: images,
        composite: composite,
        titles: titles,
      ),
  ];
  entries.sort((a, b) {
    final byStatus = a.status.index.compareTo(b.status.index);
    if (byStatus != 0) return byStatus;
    return Shot.bySource(a.shot, b.shot);
  });
  return RunDiff(
    before: before.dir,
    after: after.dir,
    entries: entries,
    beforeShell: before.manifest.shell,
    afterShell: after.manifest.shell,
    beforeSetup: before.manifest.setup,
    afterSetup: after.manifest.setup,
  );
}

/// The sheets `--composite` would write for these runs, so that a title
/// can be drawn to the width each of them has room for. Empty when no shot
/// id has an image on either side.
///
/// Sizes are read from the PNG headers, without decoding them. An entry
/// whose pixels turn out not to differ is included, because telling that
/// apart needs them; its sheet is then never written.
List<CompositeLayout> compositeLayouts(
  StoredRun before,
  StoredRun after, {
  required CompositeDirection direction,
}) {
  final beforeShots = {for (final s in before.manifest.shots) s.id: s};
  final afterShots = {for (final s in after.manifest.shots) s.id: s};
  final layouts = <CompositeLayout>[];
  for (final id in {...beforeShots.keys, ...afterShots.keys}) {
    final a = _read(before, beforeShots[id]);
    final b = _read(after, afterShots[id]);
    if (a == null && b == null) continue;
    // Identical files are identical pixels: no sheet, so no title to draw.
    if (a != null && b != null && _sameBytes(a, b)) continue;
    final sizeA = a == null ? null : _headerSize(a);
    final sizeB = b == null ? null : _headerSize(b);
    layouts.add(
      CompositeLayout((
        math.max(sizeA?.$1 ?? 0, sizeB?.$1 ?? 0),
        math.max(sizeA?.$2 ?? 0, sizeB?.$2 ?? 0),
      ), direction: direction),
    );
  }
  return layouts;
}

DiffEntry _entry(
  String id,
  StoredRun beforeRun,
  Shot? before,
  StoredRun afterRun,
  Shot? after, {
  required String? dir,
  required bool images,
  required CompositeDirection? composite,
  required Map<(int, int), img.Image> titles,
}) {
  final beforeBytes = _read(beforeRun, before);
  final afterBytes = _read(afterRun, after);
  Rgba? beforeImage;
  Rgba? afterImage;
  PixelDiff? pixels;
  if (beforeBytes != null && afterBytes != null) {
    if (_sameBytes(beforeBytes, afterBytes)) {
      // Identical files are identical pixels; skip decoding.
      pixels = const PixelDiff(differing: 0, total: 0);
    } else {
      beforeImage = Rgba.decode(beforeBytes);
      afterImage = Rgba.decode(afterBytes);
      pixels = comparePixels(beforeImage, afterImage);
    }
  }

  // An error is part of what was shot: the same error and the same image
  // on both sides is no change; a new, fixed, or different error is one.
  final DiffStatus status;
  if (before == null) {
    status = DiffStatus.added;
  } else if (after == null) {
    status = DiffStatus.removed;
  } else if (before.status != after.status ||
      before.error != after.error ||
      (beforeBytes == null) != (afterBytes == null) ||
      (pixels?.differing ?? 0) > 0) {
    status = DiffStatus.changed;
  } else {
    status = DiffStatus.unchanged;
  }

  // What a sheet can show: differing pixels, or an image on one side only.
  // A shot the code no longer has, or no longer renders, is the change.
  final oneSided = (beforeBytes == null) != (afterBytes == null);
  if (oneSided && composite != null) {
    beforeImage = beforeBytes == null ? null : Rgba.decode(beforeBytes);
    afterImage = afterBytes == null ? null : Rgba.decode(afterBytes);
  }
  final showable = oneSided || (pixels?.differing ?? 0) > 0;

  String? diffPng;
  String? compositePng;
  if (dir != null && showable) {
    final marked = diffImage(beforeImage ?? _absent, afterImage ?? _absent);
    if (images && beforeImage != null && afterImage != null) {
      diffPng = '$id.png';
      File(p.join(dir, diffPng)).writeAsBytesSync(img.encodePng(marked));
    }
    if (composite != null) {
      compositePng = '$id-composite.png';
      File(p.join(dir, compositePng)).writeAsBytesSync(
        img.encodePng(
          _sheet(
            beforeImage,
            marked,
            afterImage,
            pixels: pixels,
            direction: composite,
            titles: titles,
          ),
        ),
      );
    }
  }

  return DiffEntry(
    status: status,
    shot: (after ?? before)!,
    diffRatio: pixels?.ratio,
    beforeSize: status == DiffStatus.changed && before!.size != after!.size
        ? before.size
        : null,
    beforePng: before?.png,
    afterPng: after?.png,
    diffPng: diffPng,
    compositePng: compositePng,
  );
}

/// One entry's sheet. [pixels] is null on a one-sided entry, where every
/// pixel of the union canvas differs.
img.Image _sheet(
  Rgba? before,
  img.Image marked,
  Rgba? after, {
  required PixelDiff? pixels,
  required CompositeDirection direction,
  required Map<(int, int), img.Image> titles,
}) {
  final area = marked.width * marked.height;
  final counted = pixels ?? PixelDiff(differing: area, total: area);
  final panel = (marked.width, marked.height);
  // The title was drawn to the room this sheet has, so it goes on as it
  // is; the gutters and the caption size are known before it is rendered.
  final base = CompositeLayout(panel, direction: direction);
  final drawn = titles[base.title];
  // Only worth the room when the two sides disagree about it.
  final sizesDiffer =
      (before?.width ?? 0) != (after?.width ?? 0) ||
      (before?.height ?? 0) != (after?.height ?? 0);
  String caption(String name, Rgba? image) => switch (image) {
    null => '$name none',
    final image when sizesDiffer => '$name ${image.width}x${image.height}',
    _ => name,
  };
  return compositeDiff(
    before: before,
    diff: marked,
    after: after,
    layout: CompositeLayout(
      panel,
      direction: direction,
      titleHeight: drawn?.height ?? 0,
    ),
    captions: (
      caption('before', before),
      // The pixel count is the fact to keep when the panel is too narrow
      // to say both.
      base.fittingCaption([
        'diff ${_percent(counted.ratio)}, ${counted.differing}px',
        'diff ${counted.differing}px',
        'diff',
      ]),
      caption('after', after),
    ),
    title: drawn,
  );
}

/// A share as a percentage with four significant digits, so that a change
/// of a few pixels never reads 0, as in the report.
String _percent(double ratio) =>
    '${double.parse((ratio * 100).toStringAsPrecision(4))}%';

/// Bytes of [shot]'s PNG in [run]; null when it has none.
Uint8List? _read(StoredRun run, Shot? shot) {
  final path = shot == null ? null : run.pngPath(shot);
  if (path == null || !File(path).existsSync()) return null;
  return File(path).readAsBytesSync();
}

/// Pixel size [png] declares, without decoding it: the IHDR chunk comes
/// first, and holds the width and height as the two 32-bit words after the
/// 8-byte signature, the chunk's length and its type.
(int, int) _headerSize(Uint8List png) {
  if (png.length < 24) throw const FormatException('not a PNG');
  final header = ByteData.sublistView(png, 0, 24);
  return (header.getUint32(16), header.getUint32(20));
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

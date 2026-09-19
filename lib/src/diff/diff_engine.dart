import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../run/manifest.dart';
import '../run/run_store.dart';
import 'pixel_diff.dart';
import 'run_diff.dart';

/// Compares [before] and [after] by shot id. With [imagesDir], also
/// writes `<id>.png` there, marking the differing pixels of every
/// `changed` entry that has both images.
RunDiff diffRuns(StoredRun before, StoredRun after, {String? imagesDir}) {
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
        imagesDir: imagesDir,
      ),
  ];
  entries.sort((a, b) {
    final byStatus = a.status.index.compareTo(b.status.index);
    if (byStatus != 0) return byStatus;
    return Shot.bySource(a.shot, b.shot);
  });
  return RunDiff(before: before.dir, after: after.dir, entries: entries);
}

DiffEntry _entry(
  String id,
  StoredRun beforeRun,
  Shot? before,
  StoredRun afterRun,
  Shot? after, {
  required String? imagesDir,
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

  String? diffPng;
  if (imagesDir != null &&
      status == DiffStatus.changed &&
      beforeImage != null &&
      afterImage != null) {
    diffPng = '$id.png';
    File(p.join(imagesDir, diffPng))
        .writeAsBytesSync(img.encodePng(diffImage(beforeImage, afterImage)));
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
  );
}

/// Bytes of [shot]'s PNG in [run]; null when it has none.
Uint8List? _read(StoredRun run, Shot? shot) {
  final path = shot == null ? null : run.pngPath(shot);
  if (path == null || !File(path).existsSync()) return null;
  return File(path).readAsBytesSync();
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

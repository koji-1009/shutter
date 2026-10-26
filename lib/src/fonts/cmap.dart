import 'dart:typed_data';

/// The code points a font draws: sorted, disjoint, inclusive ranges.
class Coverage {
  /// Sorts and merges [ranges].
  Coverage(Iterable<(int, int)> ranges) : ranges = _merge(ranges);

  /// The `[start, end, start, end, ...]` list [toJson] writes.
  factory Coverage.fromJson(List<Object?> json) => Coverage([
    for (var i = 0; i + 1 < json.length; i += 2)
      (json[i]! as int, json[i + 1]! as int),
  ]);

  final List<(int, int)> ranges;

  /// How many code points it holds.
  int get size => ranges.fold(0, (sum, r) => sum + r.$2 - r.$1 + 1);

  bool contains(int codePoint) {
    var low = 0;
    var high = ranges.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final (start, end) = ranges[mid];
      if (codePoint < start) {
        high = mid - 1;
      } else if (codePoint > end) {
        low = mid + 1;
      } else {
        return true;
      }
    }
    return false;
  }

  List<int> toJson() => [
    for (final (start, end) in ranges) ...[start, end],
  ];

  static List<(int, int)> _merge(Iterable<(int, int)> ranges) {
    final sorted = ranges.toList()..sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    for (final range in sorted) {
      if (merged.isNotEmpty && range.$1 <= merged.last.$2 + 1) {
        final last = merged.removeLast();
        merged.add((last.$1, range.$2 > last.$2 ? range.$2 : last.$2));
      } else {
        merged.add(range);
      }
    }
    return merged;
  }
}

/// Reads [length] bytes of a file at [offset]; fewer at its end.
typedef ByteReader = Uint8List Function(int offset, int length);

const _ttcf = 0x74746366;
const _cmap = 0x636d6170;
const _os2 = 0x4f532f32;
const _sfntVersions = {0x00010000, 0x4f54544f, 0x74727565};

/// The code points the font in a file maps to glyphs, from its `cmap`
/// table: an OpenType or TrueType file, or the first font of a
/// collection, the one Flutter loads. Null when the file is none of
/// these, or has no Unicode `cmap` subtable shutter reads (formats 4, 12,
/// and 13).
Coverage? readCoverage(ByteReader read) {
  try {
    final cmap = _table(read, _cmap);
    return cmap == null ? null : _coverage(cmap);
  } on FormatException {
    return null;
  }
}

/// The weight class of the font in a file (400 regular, 700 bold), from
/// its `OS/2` table: of a collection, the first font's, the one Flutter
/// loads. 400 when the font has no such table or shutter cannot read it.
int readWeight(ByteReader read) {
  try {
    return _table(read, _os2)?.u16(4) ?? 400;
  } on FormatException {
    return 400;
  }
}

/// The table [tag] of the font in a file, or of the first font of a
/// collection; null when the file is not a font or the font has none.
ByteData? _table(ByteReader read, int tag) {
  ByteData bytes(int offset, int length) =>
      ByteData.sublistView(read(offset, length));
  var offset = 0;
  if (bytes(0, 4).u32(0) == _ttcf) offset = bytes(12, 4).u32(0);
  final header = bytes(offset, 12);
  if (!_sfntVersions.contains(header.u32(0))) return null;
  final count = header.u16(4);
  final records = bytes(offset + 12, count * 16);
  for (var i = 0; i < count; i++) {
    if (records.u32(i * 16) != tag) continue;
    return bytes(records.u32(i * 16 + 8), records.u32(i * 16 + 12));
  }
  return null;
}

/// Big-endian reads that fail past the end, as a truncated or malformed
/// font does.
extension on ByteData {
  int u16(int at) => at >= 0 && at + 2 <= lengthInBytes
      ? getUint16(at)
      : throw const FormatException('truncated font');

  int u32(int at) => at >= 0 && at + 4 <= lengthInBytes
      ? getUint32(at)
      : throw const FormatException('truncated font');
}

/// The union of the Unicode subtables (platforms 0 and 3) of [cmap].
Coverage? _coverage(ByteData cmap) {
  final ranges = <(int, int)>[];
  var read = false;
  for (var i = 0; i < cmap.u16(2); i++) {
    final record = 4 + i * 8;
    if (cmap.u16(record) case != 0 && != 3) continue;
    final table = cmap.u32(record + 4);
    switch (cmap.u16(table)) {
      case 4:
        _segments(cmap, table, ranges);
      case 12:
        _groups(cmap, table, ranges, sameGlyph: false);
      case 13:
        _groups(cmap, table, ranges, sameGlyph: true);
      default:
        continue;
    }
    read = true;
  }
  return read ? Coverage(ranges) : null;
}

/// Format 4: segments of 16-bit code points. A code point mapped to glyph
/// 0 is not drawn.
void _segments(ByteData cmap, int table, List<(int, int)> ranges) {
  final count = cmap.u16(table + 6) ~/ 2;
  final ends = table + 14;
  final starts = ends + count * 2 + 2;
  final deltas = starts + count * 2;
  final rangeOffsets = deltas + count * 2;
  for (var i = 0; i < count; i++) {
    final start = cmap.u16(starts + i * 2);
    final end = cmap.u16(ends + i * 2);
    if (start == 0xffff) continue;
    final delta = cmap.u16(deltas + i * 2);
    final rangeOffset = cmap.u16(rangeOffsets + i * 2);
    for (var c = start; c <= end; c++) {
      var glyph = c;
      if (rangeOffset != 0) {
        glyph = cmap.u16(rangeOffsets + i * 2 + rangeOffset + (c - start) * 2);
        if (glyph == 0) continue;
      }
      if ((glyph + delta) & 0xffff == 0) continue;
      if (ranges.isNotEmpty && ranges.last.$2 == c - 1) {
        ranges.last = (ranges.last.$1, c);
      } else {
        ranges.add((c, c));
      }
    }
  }
}

/// Formats 12 and 13: groups of 32-bit code points, mapped to consecutive
/// glyphs (12) or all to one glyph (13).
void _groups(
  ByteData cmap,
  int table,
  List<(int, int)> ranges, {
  required bool sameGlyph,
}) {
  for (var i = 0; i < cmap.u32(table + 12); i++) {
    final group = table + 16 + i * 12;
    var start = cmap.u32(group);
    final end = cmap.u32(group + 4);
    if (cmap.u32(group + 8) == 0) {
      if (sameGlyph) continue;
      start++;
    }
    if (start <= end) ranges.add((start, end));
  }
}

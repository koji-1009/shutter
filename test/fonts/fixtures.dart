import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../helpers.dart';

/// A fake google_fonts package root whose descriptors list [fonts]
/// (family → bytes, all w400 normal) plus a bold italic entry and a
/// `*TextTheme` method without `fontFamily`.
String googleFontsPackage(Map<String, List<int>> fonts) {
  final root = tempDir();
  final methods = StringBuffer();
  for (final MapEntry(key: family, value: bytes) in fonts.entries) {
    methods.writeln('''
  static TextStyle ${family.toLowerCase()}({TextStyle? textStyle}) {
    final fonts = <GoogleFontsVariant, GoogleFontsFile>{
      const GoogleFontsVariant(
        fontWeight: FontWeight.w400,
        fontStyle: FontStyle.normal,
      ): GoogleFontsFile(
        '${sha256.convert(bytes)}',
        ${bytes.length},
      ),
      const GoogleFontsVariant(
        fontWeight: FontWeight.w700,
        fontStyle: FontStyle.italic,
      ): GoogleFontsFile(
        '${'0' * 64}',
        1,
      ),
    };
    return googleFontsTextStyle(fontFamily: '$family', fonts: fonts);
  }

  static TextTheme ${family.toLowerCase()}TextTheme([TextTheme? textTheme]) {
    return TextTheme();
  }
''');
  }
  writeFiles(root, {
    'lib/src/google_fonts_parts/part_a.dart': 'class PartA {\n$methods}\n',
    'lib/src/google_fonts_parts/README.md': 'not dart',
  });
  return root;
}

/// Makes [projectRoot]'s package_config point `google_fonts` at [root].
void linkGoogleFonts(String projectRoot, String root) {
  writeFiles(projectRoot, {
    '.dart_tool/package_config.json': jsonEncode({
      'configVersion': 2,
      'packages': [
        {'name': 'other', 'rootUri': '../other'},
        {'name': 'google_fonts', 'rootUri': Uri.directory(root).toString()},
      ],
    }),
  });
}

String hashOf(List<int> bytes) => sha256.convert(bytes).toString();

/// Big-endian bytes of [values], each [width] bytes wide.
List<int> be(int width, List<int> values) => [
  for (final value in values)
    for (var i = width - 1; i >= 0; i--) (value >> (i * 8)) & 0xff,
];

/// A font file whose first table is a `cmap` holding [subtables]
/// (platform, encoding, subtable bytes), then an `OS/2` of [weight] when
/// given; the first font of a collection with [collection].
Uint8List cmapFont(
  List<(int, int, List<int>)> subtables, {
  bool collection = false,
  int? weight,
}) {
  final cmapRecords = <int>[];
  final cmapTables = <int>[];
  for (final (platform, encoding, bytes) in subtables) {
    cmapRecords.addAll([
      ...be(2, [platform, encoding]),
      ...be(4, [4 + subtables.length * 8 + cmapTables.length]),
    ]);
    cmapTables.addAll(bytes);
  }
  final tables = {
    'cmap': [
      ...be(2, [0, subtables.length]),
      ...cmapRecords,
      ...cmapTables,
    ],
    if (weight != null) 'OS/2': be(2, [0, 0, weight]),
  };
  final start = (collection ? 16 : 0) + 12 + tables.length * 16;
  final records = <int>[];
  final data = <int>[];
  for (final MapEntry(:key, :value) in tables.entries) {
    records.addAll([
      ...ascii.encode(key),
      ...be(4, [0, start + data.length, value.length]),
    ]);
    data.addAll(value);
  }
  return Uint8List.fromList([
    if (collection) ...[
      ...ascii.encode('ttcf'),
      ...be(4, [0x10000, 1, 16]),
    ],
    ...be(4, [0x10000]),
    ...be(2, [tables.length, 0, 0, 0]),
    ...records,
    ...data,
  ]);
}

/// A format 4 `cmap` subtable: segments of (start, end, delta) mapping by
/// delta, or with glyphs, mapping each code point to its glyph.
List<int> format4(List<(int, int, int, List<int>?)> segments) {
  final all = [...segments, (0xffff, 0xffff, 1, null)];
  final count = all.length;
  final glyphs = <int>[];
  final rangeOffsets = <int>[];
  for (final (i, (_, _, _, ids)) in all.indexed) {
    if (ids == null) {
      rangeOffsets.add(0);
    } else {
      rangeOffsets.add((count - i + glyphs.length) * 2);
      glyphs.addAll(ids);
    }
  }
  final body = [
    ...be(2, [count * 2, 0, 0, 0]),
    ...be(2, [for (final s in all) s.$2]),
    ...be(2, [0]),
    ...be(2, [for (final s in all) s.$1]),
    ...be(2, [for (final s in all) s.$3 & 0xffff]),
    ...be(2, rangeOffsets),
    ...be(2, glyphs),
  ];
  return [
    ...be(2, [4, body.length + 6, 0]),
    ...body,
  ];
}

/// Writes a font drawing [ranges] to [path], of [weight] when given.
void writeFont(String path, List<(int, int)> ranges, {int? weight}) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(
      cmapFont([
        (3, 10, groups(12, [for (final (s, e) in ranges) (s, e, 1)])),
      ], weight: weight),
    );
}

/// A format 12 or 13 `cmap` subtable of groups (start, end, glyph).
List<int> groups(int format, List<(int, int, int)> groups) => [
  ...be(2, [format, 0]),
  ...be(4, [16 + groups.length * 12, 0, groups.length]),
  for (final (start, end, glyph) in groups) ...be(4, [start, end, glyph]),
];

String relativeRootUri(String projectRoot, String root) => p.posix.joinAll(
  p.split(p.relative(root, from: p.join(projectRoot, '.dart_tool'))),
);

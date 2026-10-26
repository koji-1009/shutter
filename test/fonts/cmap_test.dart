import 'dart:convert';
import 'dart:typed_data';

import 'package:shutter/src/fonts/cmap.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// Reads [bytes] as a file is: fewer bytes at its end.
ByteReader readerOf(List<int> bytes) =>
    (offset, length) =>
        Uint8List.fromList(bytes.skip(offset).take(length).toList());

Coverage? coverageOf(List<int> bytes) => readCoverage(readerOf(bytes));

int weightOf(List<int> bytes) => readWeight(readerOf(bytes));

void main() {
  test('Coverage merges ranges and answers membership', () {
    final coverage = Coverage([(10, 12), (1, 3), (4, 5), (11, 20), (30, 30)]);
    expect(coverage.ranges, [(1, 5), (10, 20), (30, 30)]);
    expect(coverage.size, 17);
    expect([0, 1, 5, 6, 15, 21, 30, 31].map(coverage.contains), [
      false,
      true,
      true,
      false,
      true,
      false,
      true,
      false,
    ]);
    expect(coverage.toJson(), [1, 5, 10, 20, 30, 30]);
    expect(Coverage.fromJson(coverage.toJson()).ranges, coverage.ranges);
  });

  test('format 4 maps by delta or through glyph ids; glyph 0 is not '
      'drawn', () {
    final coverage = coverageOf(
      cmapFont([
        // 0x42 + delta is glyph 0.
        (
          3,
          1,
          format4([
            (0x41, 0x43, -0x42, null),
            (0x61, 0x63, 0, [5, 0, 7]),
          ]),
        ),
      ]),
    );
    expect(coverage!.ranges, [
      (0x41, 0x41),
      (0x43, 0x43),
      (0x61, 0x61),
      (0x63, 0x63),
    ]);
  });

  test('formats 12 and 13 group 32-bit code points', () {
    final coverage = coverageOf(
      cmapFont([
        // Glyph 0 starts the group: its first code point is not drawn.
        (3, 10, groups(12, [(0x1f600, 0x1f602, 0), (0x20000, 0x20000, 0)])),
        (0, 4, groups(12, [(0x1f680, 0x1f681, 9)])),
        // One glyph for all; glyph 0 draws none.
        (0, 6, groups(13, [(0xe000, 0xe0ff, 1), (0xf000, 0xf0ff, 0)])),
      ]),
    );
    expect(coverage!.ranges, [
      (0xe000, 0xe0ff),
      (0x1f601, 0x1f602),
      (0x1f680, 0x1f681),
    ]);
  });

  test('a collection is read through its first font', () {
    expect(
      coverageOf(
        cmapFont([
          (3, 1, format4([(0x30, 0x39, 1, null)])),
        ], collection: true),
      )!.ranges,
      [(0x30, 0x39)],
    );
  });

  test('Mac platform and other formats are not read', () {
    expect(
      coverageOf(
        cmapFont([
          (1, 0, format4([(0x41, 0x5a, 1, null)])),
          (3, 1, [0, 6, ...List.filled(10, 0)]),
        ]),
      ),
      isNull,
    );
  });

  test('a file that is not a font, is truncated, or has no cmap reads as '
      'null', () {
    expect(coverageOf(ascii.encode('not a font at all')), isNull);
    final font = cmapFont([
      (3, 1, format4([(0x41, 0x5a, 1, null)])),
    ]);
    expect(coverageOf(font.sublist(0, font.length - 4)), isNull);
    expect(coverageOf(font.sublist(0, 20)), isNull);
    final renamed = Uint8List.fromList(font)
      ..setRange(12, 16, ascii.encode('head'));
    expect(coverageOf(renamed), isNull);
  });

  test('the weight class is read from OS/2; 400 without one', () {
    final cmap = [
      (3, 1, format4([(0x41, 0x5a, 1, null)])),
    ];
    expect(weightOf(cmapFont(cmap, weight: 900)), 900);
    expect(weightOf(cmapFont(cmap, weight: 300, collection: true)), 300);
    expect(weightOf(cmapFont(cmap)), 400);
    expect(weightOf(ascii.encode('not a font at all')), 400);
    final font = cmapFont(cmap, weight: 900);
    expect(weightOf(font.sublist(0, font.length - 2)), 400);
  });
}

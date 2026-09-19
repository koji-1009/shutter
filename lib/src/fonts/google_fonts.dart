import 'dart:io';

import 'package:path/path.dart' as p;

/// One font file google_fonts can fetch: a family in one weight / style.
class const GoogleFontFile({
  /// Google Fonts family name without spaces, e.g. `NotoSansJP`.
  required final String family,

  /// 100 … 900.
  required final int weight,
  required final bool italic,

  /// sha256 of the file; also its name on `fonts.gstatic.com`.
  required final String hash,

  /// Size in bytes.
  required final int length,
}) {
  factory GoogleFontFile.fromJson(Map<String, Object?> json) => GoogleFontFile(
    family: json['family'] as String,
    weight: json['weight'] as int,
    italic: json['italic'] as bool,
    hash: json['hash'] as String,
    length: json['length'] as int,
  );

  /// Where google_fonts downloads the file from.
  Uri get url => Uri.parse('https://fonts.gstatic.com/s/a/$hash.ttf');

  /// The family name google_fonts registers and puts on its text styles:
  /// `Lobster_regular`, `NotoSansJP_700`, `NotoSansJP_italic`,
  /// `NotoSansJP_700italic`.
  String get registeredFamily {
    final weightPart = weight == 400 ? '' : '$weight';
    final stylePart = italic ? 'italic' : (weight == 400 ? 'regular' : '');
    return '${family}_$weightPart$stylePart';
  }

  /// The asset file name google_fonts looks for before fetching:
  /// `Lobster-Regular.ttf`, `NotoSansJP-BoldItalic.ttf`,
  /// `NotoSansJP-Italic.ttf`.
  String get assetName {
    final weightPart = _weightNames[weight]!;
    final variant = weightPart == 'Regular'
        ? (italic ? 'Italic' : 'Regular')
        : '$weightPart${italic ? 'Italic' : ''}';
    return '$family-$variant.ttf';
  }

  Map<String, Object?> toJson() => {
    'family': family,
    'weight': weight,
    'italic': italic,
    'hash': hash,
    'length': length,
  };
}

const _weightNames = {
  100: 'Thin',
  200: 'ExtraLight',
  300: 'Light',
  400: 'Regular',
  500: 'Medium',
  600: 'SemiBold',
  700: 'Bold',
  800: 'ExtraBold',
  900: 'Black',
};

final _method = RegExp(r'static TextStyle (\w+)\(');
final _familyLiteral = RegExp(r"fontFamily:\s*'([^']+)'");
final _variant = RegExp(
  r'GoogleFontsVariant\(\s*fontWeight:\s*FontWeight\.w(\d+),\s*'
  r'fontStyle:\s*FontStyle\.(normal|italic),?\s*\):\s*GoogleFontsFile\(\s*'
  r"'([0-9a-f]{64})',\s*(\d+),?\s*\)",
);

/// Every font file google_fonts at [root] knows, by hash, parsed from its
/// generated `lib/src/google_fonts_parts/*.dart` sources.
Map<String, GoogleFontFile> scanGoogleFonts(String root) {
  final dir = Directory(p.join(root, 'lib', 'src', 'google_fonts_parts'));
  if (!dir.existsSync()) return const {};
  final files = <String, GoogleFontFile>{};
  for (final file in dir.listSync().whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    final text = file.readAsStringSync();
    final starts = _method.allMatches(text).toList();
    for (final (i, start) in starts.indexed) {
      final end = i + 1 < starts.length ? starts[i + 1].start : text.length;
      final body = text.substring(start.start, end);
      final family = _familyLiteral.firstMatch(body)?.group(1);
      if (family == null) continue;
      for (final match in _variant.allMatches(body)) {
        final hash = match.group(3)!;
        files[hash] = GoogleFontFile(
          family: family,
          weight: int.parse(match.group(1)!),
          italic: match.group(2) == 'italic',
          hash: hash,
          length: int.parse(match.group(4)!),
        );
      }
    }
  }
  return files;
}

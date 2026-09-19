import 'dart:convert';

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

String relativeRootUri(String projectRoot, String root) => p.posix.joinAll(
  p.split(p.relative(root, from: p.join(projectRoot, '.dart_tool'))),
);

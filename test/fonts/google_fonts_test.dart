import 'dart:convert';

import 'package:shutter/src/fonts/google_fonts.dart';
import 'package:shutter/src/project/project.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'fixtures.dart';

GoogleFontFile font(int weight, {bool italic = false}) => GoogleFontFile(
  family: 'NotoSansJP',
  weight: weight,
  italic: italic,
  hash: 'h',
  length: 1,
);

void main() {
  test('names match google_fonts for every weight and style', () {
    const assets = {
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
    for (final MapEntry(key: weight, value: part) in assets.entries) {
      expect(font(weight).assetName, 'NotoSansJP-$part.ttf');
      expect(
        font(weight, italic: true).assetName,
        weight == 400
            ? 'NotoSansJP-Italic.ttf'
            : 'NotoSansJP-${part}Italic.ttf',
      );
      expect(
        font(weight).registeredFamily,
        weight == 400 ? 'NotoSansJP_regular' : 'NotoSansJP_$weight',
      );
      expect(
        font(weight, italic: true).registeredFamily,
        weight == 400 ? 'NotoSansJP_italic' : 'NotoSansJP_${weight}italic',
      );
    }
  });

  test('url and JSON round trip', () {
    final f = font(700, italic: true);
    expect(f.url.toString(), 'https://fonts.gstatic.com/s/a/h.ttf');
    final back = GoogleFontFile.fromJson(
      jsonDecode(jsonEncode(f.toJson())) as Map<String, Object?>,
    );
    expect(jsonEncode(back.toJson()), jsonEncode(f.toJson()));
  });

  test('Project.packageRoot reads package_config.json', () {
    final project = createProject();
    expect(Project.load(project).packageRoot('google_fonts'), isNull);
    writeFiles(project, {'.dart_tool/package_config.json': '{'});
    expect(Project.load(project).packageRoot('google_fonts'), isNull);
    writeFiles(project, {'.dart_tool/package_config.json': '[]'});
    expect(Project.load(project).packageRoot('google_fonts'), isNull);
    writeFiles(project, {'.dart_tool/package_config.json': '{"packages": 1}'});
    expect(Project.load(project).packageRoot('google_fonts'), isNull);
    writeFiles(project, {
      '.dart_tool/package_config.json':
          '{"packages": [1, {"name": "other", "rootUri": "x"}]}',
    });
    expect(Project.load(project).packageRoot('google_fonts'), isNull);

    final root = googleFontsPackage(const {});
    linkGoogleFonts(project, root);
    expect(Project.load(project).packageRoot('google_fonts'), root);
    writeFiles(project, {
      '.dart_tool/package_config.json': jsonEncode({
        'packages': [
          {'name': 'google_fonts', 'rootUri': relativeRootUri(project, root)},
        ],
      }),
    });
    expect(Project.load(project).packageRoot('google_fonts'), root);
  });

  test('scanGoogleFonts indexes descriptor files by hash', () {
    final bytes = utf8.encode('lobster');
    final files = scanGoogleFonts(googleFontsPackage({'Lobster': bytes}));
    expect(files.keys, {hashOf(bytes), '0' * 64});
    final regular = files[hashOf(bytes)]!;
    expect(
      [regular.family, regular.weight, regular.italic, regular.length],
      ['Lobster', 400, false, bytes.length],
    );
    final boldItalic = files['0' * 64]!;
    expect([boldItalic.weight, boldItalic.italic], [700, true]);
    expect(scanGoogleFonts(tempDir()), isEmpty);
  });
}

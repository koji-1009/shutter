import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'google_fonts.dart';

/// Downloads [url] and returns its bytes.
typedef FontFetcher = Future<Uint8List> Function(Uri url);

/// A cached font: the file on disk and what it is.
class const CachedFont(final String path, final GoogleFontFile font);

/// google_fonts files downloaded by the CLI, stored by hash in [dir]
/// (`<hash>.ttf` plus `<hash>.json` describing it).
class FontCache {
  FontCache(this.dir, {FontFetcher? fetch}) : _fetch = fetch ?? fetchUrl;

  final String dir;
  final FontFetcher _fetch;

  /// Every font in the cache.
  List<CachedFont> list() {
    final directory = Directory(dir);
    if (!directory.existsSync()) return const [];
    final fonts = <CachedFont>[];
    for (final file in directory.listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      final font = GoogleFontFile.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
      );
      final path = p.join(dir, '${font.hash}.ttf');
      if (File(path).existsSync()) fonts.add(CachedFont(path, font));
    }
    return fonts..sort((a, b) => a.path.compareTo(b.path));
  }

  /// Downloads [font], checks its length and sha256, and stores it.
  /// Returns null on success, else why it failed.
  Future<String?> add(GoogleFontFile font) async {
    final Uint8List bytes;
    try {
      bytes = await _fetch(font.url);
    } on Exception catch (e) {
      return 'download failed ($e)';
    }
    if (bytes.length != font.length) {
      return 'expected ${font.length} bytes, got ${bytes.length}';
    }
    if (sha256.convert(bytes).toString() != font.hash) {
      return 'sha256 mismatch';
    }
    Directory(dir).createSync(recursive: true);
    File(p.join(dir, '${font.hash}.ttf')).writeAsBytesSync(bytes);
    File(p.join(dir, '${font.hash}.json'))
        .writeAsStringSync(jsonEncode(font.toJson()));
    return null;
  }
}

/// Default [FontFetcher]: a plain HTTP GET that fails on non-200.
Future<Uint8List> fetchUrl(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final response = await (await client.getUrl(url)).close();
    final builder = BytesBuilder(copy: false);
    await response.forEach(builder.add);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    return builder.takeBytes();
  } finally {
    client.close();
  }
}

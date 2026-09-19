import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shutter/src/fonts/font_cache.dart';
import 'package:shutter/src/fonts/google_fonts.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'fixtures.dart';

GoogleFontFile describe(List<int> bytes, {int? length}) => GoogleFontFile(
  family: 'Lobster',
  weight: 400,
  italic: false,
  hash: hashOf(bytes),
  length: length ?? bytes.length,
);

void main() {
  final bytes = Uint8List.fromList(utf8.encode('font bytes'));

  test('add verifies and stores; list returns cached fonts', () async {
    final dir = p.join(tempDir(), 'fonts');
    final fetched = <Uri>[];
    final cache = FontCache(
      dir,
      fetch: (url) async {
        fetched.add(url);
        return bytes;
      },
    );
    expect(cache.list(), isEmpty);
    expect(await cache.add(describe(bytes)), isNull);
    expect(fetched.single.path, '/s/a/${hashOf(bytes)}.ttf');
    final cached = cache.list().single;
    expect(cached.path, p.join(dir, '${hashOf(bytes)}.ttf'));
    expect(File(cached.path).readAsBytesSync(), bytes);
    expect(cached.font.family, 'Lobster');
    File(p.join(dir, '${hashOf(bytes)}.ttf')).deleteSync();
    expect(cache.list(), isEmpty);
  });

  test('add reports length, hash, and download failures', () async {
    final dir = tempDir();
    final ok = FontCache(dir, fetch: (_) async => bytes);
    expect(await ok.add(describe(bytes, length: 3)), startsWith('expected 3'));
    expect(
      await ok.add(
        GoogleFontFile(
          family: 'Lobster',
          weight: 400,
          italic: false,
          hash: hashOf(utf8.encode('font bytez')),
          length: bytes.length,
        ),
      ),
      'sha256 mismatch',
    );
    final failing = FontCache(
      dir,
      fetch: (_) async => throw const SocketException('offline'),
    );
    expect(await failing.add(describe(bytes)), contains('download failed'));
    expect(failing.list(), isEmpty);
  });

  test('fetchUrl downloads and rejects non-200 responses', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      if (request.uri.path == '/ok') {
        request.response.add(bytes);
      } else {
        request.response.statusCode = 404;
      }
      request.response.close();
    });
    final base = 'http://${server.address.host}:${server.port}';
    expect(await fetchUrl(Uri.parse('$base/ok')), bytes);
    expect(
      () => fetchUrl(Uri.parse('$base/missing')),
      throwsA(isA<HttpException>()),
    );
  });
}

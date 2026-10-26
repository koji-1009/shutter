import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shutter/src/fonts/host_fonts.dart';
import 'package:shutter/src/project/project.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import 'fixtures.dart';

const font = writeFont;

/// Makes [path] unreadable until the test ends.
void lock(String path) {
  Process.runSync('chmod', ['000', path]);
  addTearDown(() => Process.runSync('chmod', ['755', path]));
}

void main() {
  test('hostFontDirs lists each host its font directories', () {
    expect(hostFontDirs('macos', {'HOME': '/u'}), [
      ('/System/Library/Fonts', false),
      ('/System/Library/Fonts/Supplemental', false),
      ('/Library/Fonts', true),
      ('/u/Library/Fonts', true),
    ]);
    expect(hostFontDirs('macos', {}), hasLength(3));
    expect(hostFontDirs('linux', {'HOME': '/u'}), [
      ('/usr/share/fonts', true),
      ('/usr/local/share/fonts', true),
      ('/u/.local/share/fonts', true),
      ('/u/.fonts', true),
    ]);
    expect(hostFontDirs('linux', {}), hasLength(2));
    expect(
      hostFontDirs('windows', {'WINDIR': r'D:\Win', 'LOCALAPPDATA': 'L'}),
      [(r'D:\Win\Fonts', false), (r'L\Microsoft\Windows\Fonts', false)],
    );
    expect(hostFontDirs('windows', {}), [(r'C:\Windows\Fonts', false)]);
    expect(hostFontDirs('fuchsia', {}), isEmpty);
  });

  group('HostFontIndex', () {
    test('lists font files by directory, then path, each once', () {
      final root = tempDir();
      final a = p.join(root, 'a');
      final b = p.join(root, 'b');
      font(p.join(a, 'z.ttf'), [(1, 1)]);
      font(p.join(a, 'Y.TTC'), [(1, 1)]);
      font(p.join(a, 'sub', 'x.otf'), [(1, 1)]);
      writeFiles(a, {'notes.txt': ''});
      font(p.join(b, 'deep', 'w.ttf'), [(1, 1)]);
      final locked = p.join(root, 'locked');
      font(p.join(locked, 'v.ttf'), [(1, 1)]);
      lock(locked);
      final index = HostFontIndex([
        (a, false),
        (p.join(root, 'missing'), true),
        (locked, true),
        (b, true),
        (a, true),
      ], p.join(root, 'index.json'));
      expect(index.files(), [
        (p.join(a, 'Y.TTC'), 0),
        (p.join(a, 'z.ttf'), 0),
        (p.join(b, 'deep', 'w.ttf'), 3),
        (p.join(a, 'sub', 'x.otf'), 4),
      ]);
    });

    test('reads what each font draws once, keyed by size and modification '
        'time', () {
      final root = tempDir();
      final dir = p.join(root, 'fonts');
      final cache = p.join(root, 'cache', 'index.json');
      final good = p.join(dir, 'good.ttf');
      font(good, [(0x41, 0x42)], weight: 700);
      writeFiles(dir, {'broken.ttf': 'not a font'});
      final locked = p.join(dir, 'locked.ttf');
      font(locked, [(1, 1)]);
      lock(locked);
      final index = HostFontIndex([(dir, false)], cache);
      expect(
        [
          for (final f in index.fonts()) [f.path, f.coverage.ranges, f.weight],
        ],
        [
          [
            good,
            [(0x41, 0x42)],
            700,
          ],
        ],
      );
      expect(File(cache).existsSync(), isTrue);
      expect(index.coverage(p.join(dir, 'missing.ttf')), isNull);

      // The same size and time: the cached coverage, not the new bytes.
      final modified = File(good).lastModifiedSync();
      font(good, [(0x61, 0x62)], weight: 700);
      File(good).setLastModifiedSync(modified);
      final cached = HostFontIndex([(dir, false)], cache);
      expect(cached.fonts().single.coverage.ranges, [(0x41, 0x42)]);
      File(good).setLastModifiedSync(modified.add(const Duration(days: 1)));
      expect(cached.fonts().single.coverage.ranges, [(0x61, 0x62)]);
      // Nothing new to read: the cache is kept as it is.
      final written = File(cache).lastModifiedSync();
      cached.fonts();
      expect(File(cache).lastModifiedSync(), written);
    });

    test('an unreadable cache is rebuilt', () {
      final root = tempDir();
      final dir = p.join(root, 'fonts');
      font(p.join(dir, 'f.ttf'), [(1, 2)]);
      for (final content in ['{', '[]']) {
        final cache = p.join(root, 'index.json');
        writeFiles(root, {'index.json': content});
        expect(HostFontIndex([(dir, false)], cache).fonts(), hasLength(1));
        expect(
          jsonDecode(File(cache).readAsStringSync()),
          isA<Map<String, Object?>>(),
        );
      }
    });
  });

  group('HostFallback', () {
    late String root;
    late String system;
    late String supplemental;

    setUp(() {
      root = tempDir();
      system = p.join(root, 'system');
      supplemental = p.join(root, 'supplemental');
    });

    HostFallback fallback(String os, {List<(String, bool)>? dirs}) =>
        HostFallback(
          os: os,
          index: HostFontIndex(
            dirs ?? [(system, false), (supplemental, false)],
            p.join(root, 'host', 'index.json'),
          ),
          learnedPath: p.join(root, 'host', 'fallback.json'),
        );

    test('macOS: Hiragino and Apple Color Emoji, then a font per character '
        'they lack', () {
      font(p.join(system, 'ヒラギノ角ゴシック W3.ttc'), [
        (0x20, 0x7e),
        (0x3042, 0x3042),
      ]);
      font(p.join(system, 'ヒラギノ角ゴシック W6.ttc'), [
        (0x20, 0x7e),
        (0x3042, 0x3042),
      ]);
      font(p.join(system, 'Apple Color Emoji.ttc'), [(0x1f600, 0x1f600)]);
      // A UI font, preferred over any other that draws a character.
      font(p.join(system, 'SFNS.ttf'), [(0x20, 0x17f)]);
      font(p.join(system, 'Latin.ttf'), [(0x100, 0x101)]);
      // Of two in the same directory, the one drawing fewer characters.
      font(p.join(system, 'AWide.ttf'), [(0xe00, 0xeff)]);
      font(p.join(system, 'BNarrow.ttf'), [(0xe01, 0xe02)]);
      // A placeholder for every character is never chosen.
      font(p.join(system, 'LastResort.otf'), [(0, 0x10ffff)]);
      // A later directory, even drawing fewer.
      font(p.join(supplemental, 'Tiny.ttf'), [(0xe01, 0xe01)]);
      font(p.join(supplemental, 'Tamil.ttf'), [(0xb80, 0xbff)]);
      // Nearer the regular weight, even from a later directory.
      font(p.join(system, 'Black.ttc'), [(0x1000, 0x1000)], weight: 900);
      font(p.join(supplemental, 'Light.ttc'), [(0x1000, 0x1000)], weight: 300);
      font(p.join(supplemental, 'Regular.ttc'), [(0x1000, 0x109f)]);
      final mac = fallback('macos');
      expect(mac.families(), {
        'ShutterFallbackCjk': [
          p.join(system, 'ヒラギノ角ゴシック W3.ttc'),
          p.join(system, 'ヒラギノ角ゴシック W6.ttc'),
        ],
        'ShutterFallbackEmoji': [p.join(system, 'Apple Color Emoji.ttc')],
      });
      expect(mac.cover([0x0a, 0x200d, 0x41]), isFalse);
      expect(
        mac.cover([0x0a, 0x3042, 0x101, 0xe01, 0xe02, 0xb82, 0x1000, 0x10fff0]),
        isTrue,
      );
      Map<String, List<String>> learned(HostFallback host) =>
          Map.fromEntries(host.families().entries.skip(2));
      expect(learned(mac), {
        'ShutterFallback1': [p.join(system, 'SFNS.ttf')],
        'ShutterFallback2': [p.join(supplemental, 'Tamil.ttf')],
        'ShutterFallback3': [p.join(system, 'BNarrow.ttf')],
        'ShutterFallback4': [p.join(supplemental, 'Regular.ttc')],
      });
      // Nothing new to add: the character no font draws stays as it is.
      expect(mac.cover([0xe02, 0x10fff0]), isFalse);
      // Every later run starts with them; a font removed since is skipped.
      File(p.join(supplemental, 'Tamil.ttf')).deleteSync();
      expect(learned(fallback('macos')), {
        'ShutterFallback1': [p.join(system, 'SFNS.ttf')],
        'ShutterFallback2': [p.join(system, 'BNarrow.ttf')],
        'ShutterFallback3': [p.join(supplemental, 'Regular.ttc')],
      });
    });

    test('an unreadable list of learned fonts starts empty', () {
      for (final content in ['{', '[]']) {
        writeFiles(root, {'host/fallback.json': content});
        expect(fallback('macos').families(), isEmpty);
      }
    });

    test('Windows: Yu Gothic and Segoe UI Emoji; Segoe UI preferred', () {
      font(p.join(system, 'YuGothR.ttc'), [(0x20, 0x7e)]);
      font(p.join(system, 'YuGothB.ttc'), [(0x20, 0x7e)]);
      font(p.join(system, 'seguiemj.ttf'), [(0x1f600, 0x1f600)]);
      font(p.join(system, 'Segoeui.ttf'), [(0x5d0, 0x5ea)]);
      font(p.join(system, 'Other.ttf'), [(0x5d0, 0x5d0)]);
      final windows = fallback('windows');
      expect(windows.families().keys, [
        'ShutterFallbackCjk',
        'ShutterFallbackEmoji',
      ]);
      expect(windows.cover([0x5d0]), isTrue);
      expect(windows.families()['ShutterFallback1'], [
        p.join(system, 'Segoeui.ttf'),
      ]);
    });

    test('Linux: Noto Sans CJK and Noto Color Emoji wherever they are; '
        'Noto Sans preferred', () {
      final noto = p.join(system, 'truetype', 'noto');
      font(p.join(noto, 'NotoSansCJK-Regular.ttc'), [(0x20, 0x7e)]);
      font(p.join(noto, 'NotoSansJP-Bold.otf'), [(0x20, 0x7e)]);
      font(p.join(noto, 'NotoSansCJK-Light.ttc'), [(0x20, 0x7e)]);
      font(p.join(noto, 'NotoColorEmoji.ttf'), [(0x1f600, 0x1f600)]);
      font(p.join(noto, 'NotoSansThai-Regular.ttf'), [(0xe01, 0xe5b)]);
      font(p.join(noto, 'Thai.ttf'), [(0xe01, 0xe01)]);
      final linux = fallback('linux', dirs: [(system, true)]);
      expect(linux.families(), {
        'ShutterFallbackCjk': [
          p.join(noto, 'NotoSansCJK-Regular.ttc'),
          p.join(noto, 'NotoSansJP-Bold.otf'),
        ],
        'ShutterFallbackEmoji': [p.join(noto, 'NotoColorEmoji.ttf')],
      });
      expect(linux.cover([0xe01]), isTrue);
      expect(linux.families()['ShutterFallback1'], [
        p.join(noto, 'NotoSansThai-Regular.ttf'),
      ]);
    });

    test('another host, or none of its directories, falls back to nothing '
        'but what it learns', () {
      font(p.join(system, 'Any.ttf'), [(0xe01, 0xe01)]);
      final other = fallback('fuchsia');
      expect(other.families(), isEmpty);
      expect(other.cover([0xe01]), isTrue);
      expect(other.families().keys, ['ShutterFallback1']);
      expect(fallback('macos', dirs: const []).families().keys, [
        'ShutterFallback1',
      ]);
    });

    test('forHost keeps its index and learned fonts in the project', () {
      final project = Project.load(createProject());
      final host = HostFallback.forHost(project);
      expect(host.os, Platform.operatingSystem);
      expect(host.learnedPath, p.join(project.hostFontsDir, 'fallback.json'));
      expect(host.index.cachePath, p.join(project.hostFontsDir, 'index.json'));
      expect(
        host.index.dirs,
        hostFontDirs(Platform.operatingSystem, Platform.environment),
      );
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shutter/src/fonts/host_font_list.dart';
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

  test('hostFallbackFonts starts each host with CJK, and names no family '
      'as a chosen font is named', () {
    for (final families in hostFallbackFonts.values) {
      expect(families.keys.first, 'ShutterFallbackCjk');
      for (final family in families.keys) {
        expect(family, matches(RegExp(r'^ShutterFallback[A-Z]\w*$')));
      }
    }
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
      expect(index.files, [
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
          for (final f in index.fonts) [f.path, f.coverage.ranges, f.weight],
        ],
        [
          [
            good,
            [(0x41, 0x42)],
            700,
          ],
        ],
      );
      expect(index.coverage(p.join(dir, 'missing.ttf')), isNull);
      index.save();
      expect(File(cache).existsSync(), isTrue);

      // The same size and time: the cached coverage, not the new bytes.
      final modified = File(good).lastModifiedSync();
      font(good, [(0x61, 0x62)], weight: 700);
      File(good).setLastModifiedSync(modified);
      HostFontIndex index2() => HostFontIndex([(dir, false)], cache);
      expect(index2().fonts.single.coverage.ranges, [(0x41, 0x42)]);
      File(good).setLastModifiedSync(modified.add(const Duration(days: 1)));
      final changed = index2();
      expect(changed.fonts.single.coverage.ranges, [(0x61, 0x62)]);
      changed.save();
      // Nothing new to read: the cache is kept as it is.
      final written = File(cache).lastModifiedSync();
      index2()
        ..fonts
        ..save();
      expect(File(cache).lastModifiedSync(), written);
    });

    test('a cache it cannot read, or of another version, is rebuilt', () {
      final root = tempDir();
      final dir = p.join(root, 'fonts');
      final path = p.join(dir, 'f.ttf');
      font(path, [(1, 2)]);
      final stat = File(path).statSync();
      for (final content in [
        '{',
        '[]',
        // What another version wrote, with the file's size and time.
        jsonEncode({
          'version': 0,
          'fonts': {
            path: {
              'size': stat.size,
              'modified': stat.modified.millisecondsSinceEpoch,
              'coverage': [5, 6],
              'weight': 400,
            },
          },
        }),
      ]) {
        final cache = p.join(root, 'index.json');
        writeFiles(root, {'index.json': content});
        final index = HostFontIndex([(dir, false)], cache);
        expect(index.fonts.single.coverage.ranges, [(1, 2)]);
        index.save();
        expect(jsonDecode(File(cache).readAsStringSync()), {
          'version': 1,
          'fonts': {path: isA<Map<String, Object?>>()},
        });
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

    HostFallback fallback(
      Map<String, List<String>> listed, {
      String os = 'macos',
      List<(String, bool)>? dirs,
    }) => HostFallback(
      os,
      HostFontIndex(
        dirs ?? [(system, false), (supplemental, false)],
        p.join(root, 'host', 'index.json'),
      ),
      listed,
    );

    test('loads the files listed, by name, in the order listed', () {
      font(p.join(system, 'Cjk-W3.ttc'), [(0x3042, 0x3042)]);
      font(p.join(supplemental, 'Cjk-W6.ttc'), [(0x3042, 0x3042)]);
      font(p.join(system, 'Emoji.ttc'), [(0x1f600, 0x1f600)]);
      font(p.join(system, 'noto', 'NotoSansCJKjp-Regular.otf'), [(1, 1)]);
      font(p.join(system, 'noto', 'NotoSansCJKkr-Regular.otf'), [(1, 1)]);
      // Not a file the listing holds, but one the file system finds: the
      // path it resolves to.
      final target = p.join(tempDir(), 'Linked.ttf');
      font(target, [(1, 1)]);
      Link(p.join(system, 'Link.ttf')).createSync(target);
      final listed = {
        'Cjk': ['Cjk-W3.ttc', 'Cjk-W6.ttc'],
        'Emoji': ['missing.ttc', 'emoji.TTC'],
        'None': ['missing.ttf', 'Missing*'],
        'Noto': ['NotoSansCJK*Regular*'],
        'Linked': ['Link.ttf'],
      };
      expect(
        fallback(
          listed,
          dirs: [(system, true), (supplemental, false)],
        ).families(),
        {
          'Cjk': [
            p.join(system, 'Cjk-W3.ttc'),
            p.join(supplemental, 'Cjk-W6.ttc'),
          ],
          // macOS and Windows file systems ignore case.
          'Emoji': [p.join(system, 'Emoji.ttc')],
          'Noto': [
            p.join(system, 'noto', 'NotoSansCJKjp-Regular.otf'),
            p.join(system, 'noto', 'NotoSansCJKkr-Regular.otf'),
          ],
          'Linked': [File(target).resolveSymbolicLinksSync()],
        },
      );
      // Linux ones do not.
      const lowerCase = {
        'Emoji': ['emoji.*'],
      };
      expect(fallback(lowerCase).families(), hasLength(1));
      expect(fallback(lowerCase, os: 'linux').families(), isEmpty);
    });

    test('adds a font for each character neither the fallback fonts nor '
        "the text's own fonts draw", () {
      font(p.join(system, 'Listed.ttc'), [(0x20, 0x7e), (0x3042, 0x3042)]);
      font(p.join(system, 'Own.ttf'), [(0x100, 0x100)]);
      // A placeholder for every character is never chosen.
      font(p.join(system, 'LastResort.otf'), [(0, 0x10ffff)]);
      // Of two in the same directory, the one drawing fewer characters.
      font(p.join(system, 'AWide.ttf'), [(0xe00, 0xeff)]);
      font(p.join(system, 'BNarrow.ttf'), [(0xe01, 0xe02)]);
      // A later directory, even drawing fewer.
      font(p.join(supplemental, 'Tiny.ttf'), [(0xe01, 0xe01)]);
      font(p.join(supplemental, 'Tamil.ttf'), [(0xb80, 0xbff)]);
      // Nearer the regular weight, even from a later directory.
      font(p.join(system, 'Black.ttc'), [(0x1000, 0x1000)], weight: 900);
      font(p.join(supplemental, 'Light.ttc'), [(0x1000, 0x1000)], weight: 300);
      font(p.join(supplemental, 'Regular.ttc'), [(0x1000, 0x109f)]);
      final host = fallback({
        'Listed': ['Listed.ttc'],
      });
      LaidOutText text(List<String> families, List<int> codePoints) =>
          (families: families, codePoints: codePoints.toSet());
      final ownFonts = {
        'Own': [p.join(system, 'Own.ttf')],
      };
      // Drawn by the listed font, by the text's own, or not drawn at all.
      expect(
        host.cover([
          text(['Own'], [0x0a, 0x200d, 0x41, 0x3042, 0x100]),
        ], ownFonts),
        isFalse,
      );
      expect(
        host.cover([
          text(['Own'], [0x100, 0xe01]),
          // Another style, without the font that draws U+0100.
          text(['Other'], [0x100, 0xe02, 0xb82, 0x1000, 0x10fff0]),
        ], ownFonts),
        isTrue,
      );
      expect(host.families(), {
        'Listed': [p.join(system, 'Listed.ttc')],
        'ShutterFallback1': [p.join(system, 'Own.ttf')],
        'ShutterFallback2': [p.join(supplemental, 'Tamil.ttf')],
        'ShutterFallback3': [p.join(system, 'BNarrow.ttf')],
        'ShutterFallback4': [p.join(supplemental, 'Regular.ttc')],
      });
      // Nothing new to add: the character no font draws stays as it is.
      expect(
        host.cover([
          text([], [0xe02, 0x10fff0]),
        ], const {}),
        isFalse,
      );
      // What a run chose is not kept for the next.
      expect(
        fallback({
          'Listed': ['Listed.ttc'],
        }).families().keys,
        ['Listed'],
      );
      expect(
        File(p.join(root, 'host', 'index.json')).existsSync(),
        isTrue,
        reason: 'what the fonts draw is kept',
      );
    });

    test('forHost lists the fonts of this host, with its index in the '
        'project', () {
      final project = Project.load(createProject());
      final host = HostFallback.forHost(project);
      expect(host.os, Platform.operatingSystem);
      expect(host.listed, hostFallbackFonts[Platform.operatingSystem] ?? {});
      expect(host.index.cachePath, p.join(project.hostFontsDir, 'index.json'));
      expect(
        host.index.dirs,
        hostFontDirs(Platform.operatingSystem, Platform.environment),
      );
    });
  });
}

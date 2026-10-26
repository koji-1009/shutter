import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../project/project.dart';
import 'cmap.dart';

/// Where a host keeps its fonts, most preferred first: of the fonts that
/// draw a character, one from an earlier directory is chosen. Each
/// directory says whether its subdirectories count.
List<(String, bool)> hostFontDirs(String os, Map<String, String> environment) {
  final home = environment['HOME'];
  return switch (os) {
    'macos' => [
      ('/System/Library/Fonts', false),
      ('/System/Library/Fonts/Supplemental', false),
      ('/Library/Fonts', true),
      if (home != null) ('$home/Library/Fonts', true),
    ],
    'linux' => [
      ('/usr/share/fonts', true),
      ('/usr/local/share/fonts', true),
      if (home != null) ('$home/.local/share/fonts', true),
      if (home != null) ('$home/.fonts', true),
    ],
    'windows' => [
      ('${environment['WINDIR'] ?? r'C:\Windows'}\\Fonts', false),
      if (environment['LOCALAPPDATA'] case final local?)
        ('$local\\Microsoft\\Windows\\Fonts', false),
    ],
    _ => const [],
  };
}

/// A host font file: its directory's place in the preference order, what
/// it draws, and its weight class.
class const HostFont(
  final String path,
  final int rank,
  final Coverage coverage,
  final int weight,
);

const _fontExtensions = {'.ttf', '.otf', '.ttc'};

/// The host's font files under [dirs], what each draws, and its weight.
/// Both are read from the file once and kept in [cachePath], by path,
/// size, and modification time.
class HostFontIndex(final List<(String, bool)> dirs, final String cachePath) {
  late final Map<String, Object?> _cache = _readCache();
  var _changed = false;

  /// Every font file under [dirs], in preference order: by directory,
  /// then by path. A file is listed under the first directory holding it.
  List<(String, int)> files() {
    final seen = <String>{};
    final files = <(String, int)>[];
    for (final (rank, (dir, recursive)) in dirs.indexed) {
      final directory = Directory(dir);
      if (!directory.existsSync()) continue;
      final List<String> paths;
      try {
        paths = [
          for (final entity in directory.listSync(
            recursive: recursive,
            followLinks: false,
          ))
            if (entity is File &&
                _fontExtensions.contains(
                  p.extension(entity.path).toLowerCase(),
                ))
              entity.path,
        ]..sort();
      } on FileSystemException {
        continue;
      }
      for (final path in paths) {
        if (seen.add(path)) files.add((path, rank));
      }
    }
    return files;
  }

  /// Every font file under [dirs] that shutter can read, in the order of
  /// [files].
  List<HostFont> fonts() {
    final fonts = [
      for (final (path, rank) in files())
        if (_entry(path) case (final coverage?, final weight))
          HostFont(path, rank, coverage, weight),
    ];
    _save();
    return fonts;
  }

  /// What the font at [path] draws; null when it is not a font shutter
  /// can read.
  Coverage? coverage(String path) => _entry(path).$1;

  (Coverage?, int) _entry(String path) {
    final file = File(path);
    final stat = file.statSync();
    if (stat.type == FileSystemEntityType.notFound) return (null, 400);
    final modified = stat.modified.millisecondsSinceEpoch;
    if (_cache[path]
        case {
          'size': final int size,
          'modified': final int cachedModified,
          'coverage': final List<Object?>? json,
          'weight': final int weight,
        }
        when size == stat.size && cachedModified == modified) {
      return (json == null ? null : Coverage.fromJson(json), weight);
    }
    final (coverage, weight) = _read(file);
    _cache[path] = {
      'size': stat.size,
      'modified': modified,
      'coverage': coverage?.toJson(),
      'weight': weight,
    };
    _changed = true;
    return (coverage, weight);
  }

  static (Coverage?, int) _read(File file) {
    RandomAccessFile? handle;
    try {
      final open = handle = file.openSync();
      Uint8List read(int offset, int length) {
        open.setPositionSync(offset);
        return open.readSync(length);
      }

      return (readCoverage(read), readWeight(read));
    } on FileSystemException {
      return (null, 400);
    } finally {
      handle?.closeSync();
    }
  }

  Map<String, Object?> _readCache() {
    try {
      final json = jsonDecode(File(cachePath).readAsStringSync());
      if (json is Map<String, Object?>) return json;
    } on FileSystemException {
      // No cache yet.
    } on FormatException {
      // A cache this version cannot read is rebuilt.
    }
    return {};
  }

  void _save() {
    if (!_changed) return;
    File(cachePath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(_cache));
    _changed = false;
  }
}

/// The host fonts a run falls back to, by family, in fallback order. First
/// the host's CJK fonts, with Japanese forms for the Han characters CJK
/// scripts share, and its emoji font; then a font for each character
/// those do not draw, chosen by [cover] and kept in [learnedPath] for
/// every later run of the project.
class HostFallback {
  HostFallback({
    required this.os,
    required this.index,
    required this.learnedPath,
  });

  /// The fallback of this machine for [project].
  factory HostFallback.forHost(Project project) {
    final dir = project.hostFontsDir;
    return HostFallback(
      os: Platform.operatingSystem,
      index: HostFontIndex(
        hostFontDirs(Platform.operatingSystem, Platform.environment),
        p.join(dir, 'index.json'),
      ),
      learnedPath: p.join(dir, 'fallback.json'),
    );
  }

  /// `Platform.operatingSystem` of the host.
  final String os;
  final HostFontIndex index;
  final String learnedPath;

  /// Family name → font files, in fallback order.
  Map<String, List<String>> families() {
    final learned = [
      for (final path in _learned)
        if (File(path).existsSync()) path,
    ];
    return {
      for (final MapEntry(:key, :value) in _base().entries)
        if (value.isNotEmpty) key: value,
      for (final (i, path) in learned.indexed)
        'ShutterFallback${i + 1}': [path],
    };
  }

  /// Adds a font for each character of [codePoints] the fallback fonts do
  /// not draw. Of the host fonts that draw it, the first of the host's
  /// system fonts for common scripts is chosen. Else the one nearest the
  /// regular weight: it is the only weight loaded, and a collection whose
  /// first font is black draws all its text black. Of those, the one in
  /// the most preferred directory, and of those the one drawing the fewest
  /// characters: a font for the character's script rather than one for
  /// many. Returns whether a font was added.
  bool cover(Iterable<int> codePoints) {
    final wanted = {
      for (final c in codePoints)
        if (!_invisible(c)) c,
    };
    if (wanted.isEmpty) return false;
    final chain = [for (final paths in families().values) ...paths];
    final drawn = [for (final path in chain) ?index.coverage(path)];
    final missing = [
      for (final c in wanted)
        if (!drawn.any((coverage) => coverage.contains(c))) c,
    ]..sort();
    if (missing.isEmpty) return false;
    final fonts = [
      for (final font in index.fonts())
        if (!chain.contains(font.path) &&
            !_placeholders.contains(p.basename(font.path)))
          font,
    ];
    final preferred = [
      for (final path in _preferred())
        ?fonts.where((font) => font.path == path).firstOrNull,
    ];
    final added = <HostFont>[];
    for (final c in missing) {
      if (added.any((font) => font.coverage.contains(c))) continue;
      var best = preferred
          .where((font) => font.coverage.contains(c))
          .firstOrNull;
      // [fonts] are in directory order: of those as near the regular
      // weight, the first that draws it is in the most preferred
      // directory.
      if (best == null) {
        for (final font in fonts) {
          if (!font.coverage.contains(c)) continue;
          final distance = (font.weight - 400).abs();
          final bestDistance = best == null ? 0 : (best.weight - 400).abs();
          if (best == null ||
              distance < bestDistance ||
              (distance == bestDistance &&
                  font.rank == best.rank &&
                  font.coverage.size < best.coverage.size)) {
            best = font;
          }
        }
      }
      if (best != null) added.add(best);
    }
    if (added.isEmpty) return false;
    _learned = [..._learned, for (final font in added) font.path];
    File(learnedPath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'fonts': _learned}));
    return true;
  }

  late List<String> _learned = _readLearned();

  List<String> _readLearned() {
    try {
      final Object? json = jsonDecode(File(learnedPath).readAsStringSync());
      if (json case {'fonts': final List<Object?> fonts}) {
        return fonts.whereType<String>().toList();
      }
    } on FileSystemException {
      // Nothing learned yet.
    } on FormatException {
      // Unreadable: learned again.
    }
    return const [];
  }

  /// The files of [names] in the host's first font directory that exist.
  /// Exact paths: macOS lists Japanese file names decomposed (NFD), which
  /// never equal a literal.
  List<String> _existing(List<String> names) => [
    for (final name in names)
      if (index.dirs.isNotEmpty &&
          File(p.join(index.dirs.first.$1, name)).existsSync())
        p.join(index.dirs.first.$1, name),
  ];

  /// The host's system fonts for what several host fonts draw: its UI font
  /// (for Latin, Greek, and Cyrillic beyond what the CJK font has), then
  /// Simplified Chinese, Hangul, Thai, Arabic, Hebrew, and Devanagari.
  List<String> _preferred() => switch (os) {
    'macos' => _existing([
      'SFNS.ttf',
      'Hiragino Sans GB.ttc',
      'AppleSDGothicNeo.ttc',
      'ThonburiUI.ttc',
      'SFArabic.ttf',
      'SFHebrew.ttf',
      'Kohinoor.ttc',
    ]),
    'windows' => _existing([
      'Segoeui.ttf',
      'Msyh.ttc',
      'Malgun.ttf',
      'Leelawui.ttf',
      'Nirmala.ttf',
    ]),
    'linux' => [
      for (final name in const [
        'NotoSans-Regular.ttf',
        'DejaVuSans.ttf',
        'NotoSansThai-Regular.ttf',
        'NotoSansArabic-Regular.ttf',
        'NotoSansHebrew-Regular.ttf',
        'NotoSansDevanagari-Regular.ttf',
      ])
        for (final (path, _) in index.files())
          if (p.basename(path) == name) path,
    ],
    _ => const [],
  };

  /// The host's CJK and emoji fonts.
  Map<String, List<String>> _base() {
    switch (os) {
      case 'macos':
        return {
          'ShutterFallbackCjk': _existing([
            'ヒラギノ角ゴシック W3.ttc',
            'ヒラギノ角ゴシック W6.ttc',
          ]),
          'ShutterFallbackEmoji': _existing(['Apple Color Emoji.ttc']),
        };
      case 'windows':
        return {
          'ShutterFallbackCjk': _existing(['YuGothR.ttc', 'YuGothB.ttc']),
          'ShutterFallbackEmoji': _existing(['seguiemj.ttf']),
        };
      case 'linux':
        final cjk = <String>[];
        final emoji = <String>[];
        for (final (path, _) in index.files()) {
          final name = p.basename(path);
          if ((name.startsWith('NotoSansCJK') ||
                  name.startsWith('NotoSansJP')) &&
              (name.contains('Regular') || name.contains('Bold'))) {
            cjk.add(path);
          } else if (name == 'NotoColorEmoji.ttf') {
            emoji.add(path);
          }
        }
        return {'ShutterFallbackCjk': cjk, 'ShutterFallbackEmoji': emoji};
    }
    return const {};
  }
}

/// Fonts that draw every character as a placeholder, which the host shows
/// only when nothing else draws it.
const _placeholders = {'LastResort.otf'};

/// Characters no font is chosen for: controls, format characters (joiners,
/// direction marks), and variation selectors.
bool _invisible(int c) =>
    c < 0x20 ||
    (c >= 0x7f && c <= 0x9f) ||
    (c >= 0x200b && c <= 0x200f) ||
    (c >= 0x2028 && c <= 0x202e) ||
    (c >= 0x2060 && c <= 0x206f) ||
    (c >= 0xfe00 && c <= 0xfe0f) ||
    c == 0xfeff ||
    (c >= 0xe0000 && c <= 0xe01ef);

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../project/project.dart';
import 'cmap.dart';
import 'host_font_list.dart';

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

/// Text of one style laid out in a shot: the style's own font families
/// (`fontFamily`, then `fontFamilyFallback`) and its characters beyond
/// ASCII.
typedef LaidOutText = ({List<String> families, Set<int> codePoints});

/// A host font file: its directory's place in the preference order, what
/// it draws, and its weight class.
class const HostFont(
  final String path,
  final int rank,
  final Coverage coverage,
  final int weight,
);

const _fontExtensions = {'.ttf', '.otf', '.ttc'};

/// Raised when what the index records of a font changes, so an index an
/// earlier version wrote is read anew.
const _indexVersion = 1;

/// The host's font files under [dirs], and what each font file draws and
/// its weight. Those are read from the file once and kept in [cachePath],
/// by path, size, and modification time.
class HostFontIndex(final List<(String, bool)> dirs, final String cachePath) {
  late final Map<String, Object?> _cache = _readCache();
  final _entries = <String, (Coverage?, int)>{};
  var _changed = false;

  /// Every font file under [dirs], in preference order: by directory,
  /// then by path. A file is listed under the first directory holding it.
  late final List<(String, int)> files = _list();

  /// Every font file under [dirs] that shutter can read, in the order of
  /// [files].
  late final List<HostFont> fonts = [
    for (final (path, rank) in files)
      if (_entry(path) case (final coverage?, final weight))
        HostFont(path, rank, coverage, weight),
  ];

  /// What the font at [path] draws; null when it is not a font shutter
  /// can read. Any font file, under [dirs] or not.
  Coverage? coverage(String path) => _entry(path).$1;

  /// Writes what was read since it was last saved to [cachePath].
  void save() {
    if (!_changed) return;
    File(cachePath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({'version': _indexVersion, 'fonts': _cache}),
      );
    _changed = false;
  }

  List<(String, int)> _list() {
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

  (Coverage?, int) _entry(String path) => _entries[path] ??= _load(path);

  (Coverage?, int) _load(String path) {
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
      final Object? json = jsonDecode(File(cachePath).readAsStringSync());
      if (json case {
        'version': _indexVersion,
        'fonts': final Map<String, Object?> fonts,
      }) {
        return fonts;
      }
    } on FileSystemException {
      // No cache yet.
    } on FormatException {
      // Unreadable: rebuilt.
    }
    return {};
  }
}

/// The host fonts one run falls back to, by family, in fallback order:
/// [listed], then a font for each character neither those nor the text's
/// own fonts draw, chosen by [cover]. What is chosen lasts for the run
/// only, so the same text falls back to the same fonts in every run.
class HostFallback(
  /// `Platform.operatingSystem` of the host.
  final String os,

  /// The host's font files.
  final HostFontIndex index,

  /// Family → file names, as [hostFallbackFonts] lists them for the host.
  final Map<String, List<String>> listed,
) {
  /// The fallback of this machine, with its index in [project].
  factory HostFallback.forHost(Project project) => HostFallback(
    Platform.operatingSystem,
    HostFontIndex(
      hostFontDirs(Platform.operatingSystem, Platform.environment),
      p.join(project.hostFontsDir, 'index.json'),
    ),
    hostFallbackFonts[Platform.operatingSystem] ?? const {},
  );

  late final Map<String, List<String>> _listed = {
    for (final MapEntry(key: family, value: names) in listed.entries)
      if ([for (final name in names) ..._files(name)] case final paths
          when paths.isNotEmpty)
        family: paths,
  };

  final _chosen = <String>[];

  /// Family → font files, in fallback order.
  Map<String, List<String>> families() => {
    ..._listed,
    for (final (i, path) in _chosen.indexed) 'ShutterFallback${i + 1}': [path],
  };

  /// Adds a font for each character of [texts] that neither the fallback
  /// fonts nor the text's own fonts ([fontFiles] by family) draw. Of the
  /// host fonts that draw it, the one nearest the regular weight is
  /// chosen: it is the only weight loaded, and a collection whose first
  /// font is black draws all its text black. Of those, the one in the most
  /// preferred directory, and of those the one drawing the fewest
  /// characters: a font for the character's script rather than one for
  /// many. Returns whether a font was added.
  bool cover(Iterable<LaidOutText> texts, Map<String, List<String>> fontFiles) {
    final chain = [for (final paths in families().values) ...paths];
    final missing = <int>{};
    for (final text in texts) {
      final fonts = [
        for (final family in text.families) ...?fontFiles[family],
        ...chain,
      ];
      for (final c in text.codePoints) {
        if (_invisible(c) || missing.contains(c)) continue;
        if (!fonts.any((path) => index.coverage(path)?.contains(c) ?? false)) {
          missing.add(c);
        }
      }
    }
    final added = <HostFont>[];
    if (missing.isNotEmpty) {
      final candidates = [
        for (final font in index.fonts)
          if (!chain.contains(font.path) &&
              !_placeholders.contains(p.basename(font.path)))
            font,
      ];
      for (final c in missing.toList()..sort()) {
        if (added.any((font) => font.coverage.contains(c))) continue;
        // [candidates] are in directory order: of those as near the
        // regular weight, the first that draws it is in the most
        // preferred directory.
        HostFont? best;
        for (final font in candidates) {
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
        if (best != null) added.add(best);
      }
    }
    index.save();
    _chosen.addAll([for (final font in added) font.path]);
    return added.isNotEmpty;
  }

  /// The host font files [name] names, in directory order. Matched
  /// without case where the host's file system ignores it.
  List<String> _files(String name) {
    final pattern = RegExp(
      '^${name.split('*').map(RegExp.escape).join('.*')}\$',
      caseSensitive: os == 'linux',
    );
    final files = [
      for (final (path, _) in index.files)
        if (pattern.hasMatch(p.basename(path))) path,
    ];
    if (files.isNotEmpty || name.contains('*')) return files;
    // A name the listing spells otherwise: macOS lists Japanese file names
    // decomposed (NFD), which never equal a literal. The file system finds
    // it, and resolves it to the path it lists.
    for (final (dir, _) in index.dirs) {
      final file = File(p.join(dir, name));
      if (file.existsSync()) return [file.resolveSymbolicLinksSync()];
    }
    return const [];
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

/// The host fonts every run falls back to, by host
/// (`Platform.operatingSystem`), in fallback order: family → the font
/// files it loads, by file name, found in the host's font directories.
///
/// * The engine picks one font of a family by weight, not by glyph, so a
///   family holds one script, with a file per weight.
/// * The first family is CJK with Japanese forms: a Han character takes
///   the Japanese form when that font has it.
/// * A file name may hold `*`, matching any run of characters; every file
///   it matches is loaded. A file the host lacks is skipped.
/// * A character none of these draw falls back to another host font,
///   chosen for that run (`HostFallback.cover`).
const hostFallbackFonts = <String, Map<String, List<String>>>{
  'macos': {
    'ShutterFallbackCjk': ['ヒラギノ角ゴシック W3.ttc', 'ヒラギノ角ゴシック W6.ttc'],
    'ShutterFallbackEmoji': ['Apple Color Emoji.ttc'],
    'ShutterFallbackUi': ['SFNS.ttf'],
    'ShutterFallbackHans': ['Hiragino Sans GB.ttc'],
    'ShutterFallbackHangul': ['AppleSDGothicNeo.ttc'],
    'ShutterFallbackThai': ['ThonburiUI.ttc'],
    'ShutterFallbackArabic': ['SFArabic.ttf'],
    'ShutterFallbackHebrew': ['SFHebrew.ttf'],
    'ShutterFallbackDevanagari': ['Kohinoor.ttc'],
  },
  'linux': {
    // Noto Sans CJK holds every CJK script in each of its faces.
    'ShutterFallbackCjk': [
      'NotoSansCJK*Regular*',
      'NotoSansCJK*Bold*',
      'NotoSansJP*Regular*',
      'NotoSansJP*Bold*',
    ],
    'ShutterFallbackEmoji': ['NotoColorEmoji.ttf'],
    'ShutterFallbackUi': ['NotoSans-Regular.ttf', 'NotoSans-Bold.ttf'],
    'ShutterFallbackThai': [
      'NotoSansThai-Regular.ttf',
      'NotoSansThai-Bold.ttf',
    ],
    'ShutterFallbackArabic': [
      'NotoSansArabic-Regular.ttf',
      'NotoSansArabic-Bold.ttf',
    ],
    'ShutterFallbackHebrew': [
      'NotoSansHebrew-Regular.ttf',
      'NotoSansHebrew-Bold.ttf',
    ],
    'ShutterFallbackDevanagari': [
      'NotoSansDevanagari-Regular.ttf',
      'NotoSansDevanagari-Bold.ttf',
    ],
  },
  'windows': {
    'ShutterFallbackCjk': ['YuGothR.ttc', 'YuGothB.ttc'],
    'ShutterFallbackEmoji': ['seguiemj.ttf'],
    // Segoe UI holds Arabic and Hebrew too.
    'ShutterFallbackUi': ['Segoeui.ttf', 'Segoeuib.ttf'],
    'ShutterFallbackHans': ['Msyh.ttc', 'Msyhbd.ttc'],
    'ShutterFallbackHangul': ['Malgun.ttf', 'Malgunbd.ttf'],
    'ShutterFallbackThai': ['Leelawui.ttf', 'Leelauib.ttf'],
    'ShutterFallbackDevanagari': ['Nirmala.ttf', 'Nirmalab.ttf'],
  },
};

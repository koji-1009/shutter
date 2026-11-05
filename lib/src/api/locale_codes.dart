import '../shutter_exception.dart';

/// A language (an ISO 639 code), an optional script, and an optional
/// region, joined by `-` or `_`, as `Locale.fromSubtags` takes them.
final _languageTag = RegExp(
  r'^([a-zA-Z]{2,3})(?:[-_]([a-zA-Z]{4}))?(?:[-_]([a-zA-Z]{2}|[0-9]{3}))?$',
);

/// The language, script, and country codes of [tag] as the app receives
/// them: each in its usual case (`ja`, `Hant`, `JP`), and a deprecated
/// language or region replaced as `dart:ui`'s `Locale` replaces it
/// (`iw` is `he`). Throws a usage error for anything else.
(String, String?, String?) localeCodes(String tag) {
  final match = _languageTag.firstMatch(tag);
  if (match == null) {
    throw ShutterException.usage(
      'locale must be a language, then an optional script and region, '
      'e.g. ja-JP or zh-Hant-TW (got "$tag").',
    );
  }
  final language = match.group(1)!.toLowerCase();
  final script = match.group(2);
  final country = match.group(3)?.toUpperCase();
  return (
    _deprecatedLanguages[language] ?? language,
    script == null
        ? null
        : '${script[0].toUpperCase()}${script.substring(1).toLowerCase()}',
    _deprecatedRegions[country] ?? country,
  );
}

/// [codes] as a language tag: `ja-JP`, `zh-Hant-TW`.
String languageTag((String, String?, String?) codes) {
  final (language, script, country) = codes;
  return [language, ?script, ?country].join('-');
}

/// `dart:ui`'s `Locale._deprecatedLanguageSubtagMap`: a deprecated
/// language subtag and the one `Locale.languageCode` gives for it.
const _deprecatedLanguages = {
  'in': 'id',
  'iw': 'he',
  'ji': 'yi',
  'jw': 'jv',
  'mo': 'ro',
  'aam': 'aas',
  'adp': 'dz',
  'aue': 'ktz',
  'ayx': 'nun',
  'bgm': 'bcg',
  'bjd': 'drl',
  'ccq': 'rki',
  'cjr': 'mom',
  'cka': 'cmr',
  'cmk': 'xch',
  'coy': 'pij',
  'cqu': 'quh',
  'drh': 'khk',
  'drw': 'prs',
  'gav': 'dev',
  'gfx': 'vaj',
  'ggn': 'gvr',
  'gti': 'nyc',
  'guv': 'duz',
  'hrr': 'jal',
  'ibi': 'opa',
  'ilw': 'gal',
  'jeg': 'oyb',
  'kgc': 'tdf',
  'kgh': 'kml',
  'koj': 'kwv',
  'krm': 'bmf',
  'ktr': 'dtp',
  'kvs': 'gdj',
  'kwq': 'yam',
  'kxe': 'tvd',
  'kzj': 'dtp',
  'kzt': 'dtp',
  'lii': 'raq',
  'lmm': 'rmx',
  'meg': 'cir',
  'mst': 'mry',
  'mwj': 'vaj',
  'myt': 'mry',
  'nad': 'xny',
  'ncp': 'kdz',
  'nnx': 'ngv',
  'nts': 'pij',
  'oun': 'vaj',
  'pcr': 'adx',
  'pmc': 'huw',
  'pmu': 'phr',
  'ppa': 'bfy',
  'ppr': 'lcq',
  'pry': 'prt',
  'puz': 'pub',
  'sca': 'hle',
  'skk': 'oyb',
  'tdu': 'dtp',
  'thc': 'tpo',
  'thx': 'oyb',
  'tie': 'ras',
  'tkk': 'twm',
  'tlw': 'weo',
  'tmp': 'tyj',
  'tne': 'kak',
  'tnf': 'prs',
  'tsf': 'taj',
  'uok': 'ema',
  'xba': 'cax',
  'xia': 'acn',
  'xkh': 'waw',
  'xsj': 'suj',
  'ybd': 'rki',
  'yma': 'lrr',
  'ymt': 'mtm',
  'yos': 'zom',
  'yuu': 'yug',
};

/// `dart:ui`'s `Locale._deprecatedRegionSubtagMap`: a deprecated region
/// subtag and the one `Locale.countryCode` gives for it.
const _deprecatedRegions = {
  'BU': 'MM',
  'DD': 'DE',
  'FX': 'FR',
  'TP': 'TL',
  'YD': 'YE',
  'ZR': 'CD',
};

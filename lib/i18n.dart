// Translations shared with the Immich web and mobile clients (assets/i18n, from
// the immich repo's i18n/ folder) plus a few strings only this app needs
// (assets/i18n_app). Messages use ICU syntax, e.g. "{count, plural, one {# item} other {# items}}".
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Native language names for the language picker (the web asks the browser for these).
const languageNames = <String, String>{
  'af': 'Afrikaans', 'ar': 'العربية', 'az': 'Azərbaycanca', 'be': 'Беларуская',
  'bg': 'Български', 'bi': 'Bislama', 'bn': 'বাংলা', 'br': 'Brezhoneg', 'bs': 'Bosanski',
  'ca': 'Català', 'cs': 'Čeština', 'cv': 'Чӑвашла', 'da': 'Dansk', 'de': 'Deutsch',
  'de_CH': 'Deutsch (Schweiz)', 'el': 'Ελληνικά', 'en': 'English', 'en_GB': 'English (UK)',
  'eo': 'Esperanto', 'es': 'Español', 'et': 'Eesti', 'eu': 'Euskara', 'fa': 'فارسی',
  'fi': 'Suomi', 'fil': 'Filipino', 'fr': 'Français', 'ga': 'Gaeilge', 'gl': 'Galego',
  'gsw': 'Schwiizertüütsch', 'gu': 'ગુજરાતી', 'he': 'עברית', 'hi': 'हिन्दी', 'hr': 'Hrvatski',
  'hu': 'Magyar', 'hy': 'Հայերեն', 'id': 'Bahasa Indonesia', 'is': 'Íslenska',
  'it': 'Italiano', 'ja': '日本語', 'ka': 'ქართული', 'kab': 'Taqbaylit', 'kk': 'Қазақ',
  'km': 'ខ្មែរ', 'kmr': 'Kurmancî', 'kn': 'ಕನ್ನಡ', 'ko': '한국어', 'kxm': 'ខ្មែរលើ',
  'lb': 'Lëtzebuergesch', 'lmo': 'Lombard', 'lt': 'Lietuvių', 'lv': 'Latviešu',
  'mfa': 'Bahasa Melayu Pattani', 'mi': 'Māori', 'mk': 'Македонски', 'ml': 'മലയാളം',
  'mn': 'Монгол', 'mr': 'मराठी', 'ms': 'Bahasa Melayu', 'nb_NO': 'Norsk bokmål',
  'ne': 'नेपाली', 'nl': 'Nederlands', 'nn': 'Norsk nynorsk', 'pa': 'ਪੰਜਾਬੀ', 'pl': 'Polski',
  'pt': 'Português', 'pt_BR': 'Português (Brasil)', 'ro': 'Română', 'ru': 'Русский',
  'si': 'සිංහල', 'sk': 'Slovenčina', 'sl': 'Slovenščina', 'sq': 'Shqip',
  'sr_Cyrl': 'Српски (ћирилица)', 'sr_Latn': 'Srpski (latinica)', 'sv': 'Svenska',
  'sw': 'Kiswahili', 'swg': 'Schwäbisch', 'ta': 'தமிழ்', 'te': 'తెలుగు', 'th': 'ไทย',
  'tl': 'Tagalog', 'tr': 'Türkçe', 'uk': 'Українська', 'ur': 'اردو', 'uz': 'Oʻzbekcha',
  'vi': 'Tiếng Việt', 'yue_Hant': '粵語 (繁體)', 'zh_Hans': '简体中文', 'zh_Hant': '繁體中文',
};

const _rtl = {'ar', 'fa', 'he', 'ur'};

class I18n extends ChangeNotifier {
  int _loadGeneration = 0;
  String _code = 'en';
  String _dateLocale = 'en';
  Map<String, String> _base = {};
  Map<String, String> _lang = {};

  String get code => _code;
  /// Locale name for `intl` date formatting (e.g. 'hu', 'zh').
  String get dateLocale => _dateLocale;
  bool get isRtl => _rtl.contains(_code.split('_').first);

  Future<Map<String, String>> _read(String path) async {
    try {
      return flatten(jsonDecode(await rootBundle.loadString(path)) as Map<String, dynamic>);
    } catch (_) {
      return {};
    }
  }

  Future<void> load(String code) async {
    final generation = ++_loadGeneration;
    if (!languageNames.containsKey(code)) code = 'en';
    final base = {
      ...await _read('assets/i18n/en.json'),
      ...await _read('assets/i18n_app/en.json'),
    };
    final lang = code == 'en'
        ? <String, String>{}
        : {
            ...await _read('assets/i18n/$code.json'),
            ...await _read('assets/i18n_app/$code.json'),
          };
    final dateLocale = await _pickDateLocale(code);
    if (generation != _loadGeneration) return; // a newer language choice won
    _base = base;
    _lang = lang;
    _code = code;
    _dateLocale = dateLocale;
    Intl.defaultLocale = _dateLocale;
    notifyListeners();
  }

  static Future<String> _pickDateLocale(String code) async {
    for (final candidate in [code, code.split('_').first, 'en']) {
      try {
        await initializeDateFormatting(candidate);
        if (DateFormat.localeExists(candidate)) return candidate;
      } catch (_) {}
    }
    return 'en';
  }

  /// Test hook: use in-memory messages.
  @visibleForTesting
  void setMessages(Map<String, String> base, Map<String, String> lang, String code) {
    _base = base;
    _lang = lang;
    _code = code;
    _dateLocale = code;
  }

  String t(String key, [Map<String, Object?> args = const {}]) {
    final raw = _lang[key];
    final msg = (raw == null || raw.isEmpty) ? _base[key] : raw;
    if (msg == null) return key;
    try {
      // Some web strings carry markup like <b>…</b>; plain text here.
      return IcuFormat(msg, args, _dateLocale).format().replaceAll(_tags, '');
    } catch (_) {
      return msg;
    }
  }

  /// Nested JSON objects become dotted keys ("admin.create_job"), like svelte-i18n.
  static Map<String, String> flatten(Map<String, dynamic> j, [String prefix = '']) {
    final out = <String, String>{};
    j.forEach((k, v) {
      final key = prefix.isEmpty ? k : '$prefix.$k';
      if (v is Map<String, dynamic>) {
        out.addAll(flatten(v, key));
      } else if (v != null) {
        out[key] = '$v';
      }
    });
    return out;
  }
}

final _tags = RegExp(r'</?[a-zA-Z]+>');

/// The app-wide translator.
final i18n = I18n();

/// Translate [key] with optional ICU [args].
String t(String key, [Map<String, Object?> args = const {}]) => i18n.t(key, args);

/// Minimal ICU MessageFormat: {arg}, plural (=N, zero/one/two/few/many/other, #),
/// select, and apostrophe quoting. Enough for Immich's translation files.
class IcuFormat {
  final String src;
  final Map<String, Object?> args;
  final String locale;
  int _i = 0;

  IcuFormat(this.src, this.args, this.locale);

  String format() => _message(null);

  /// Reads until the closing '}' of the current block (or end). [hash] replaces '#'.
  String _message(num? hash) {
    final out = StringBuffer();
    while (_i < src.length) {
      final c = src[_i];
      if (c == '}') return out.toString();
      if (c == '{') {
        out.write(_argument());
      } else if (c == "'") {
        out.write(_quoted());
      } else if (c == '#' && hash != null) {
        out.write(_formatNumber(hash));
        _i++;
      } else {
        out.write(c);
        _i++;
      }
    }
    return out.toString();
  }

  String _quoted() {
    // '' is a literal apostrophe; '{...}' quotes syntax characters; otherwise literal.
    if (_i + 1 < src.length && src[_i + 1] == "'") {
      _i += 2;
      return "'";
    }
    if (_i + 1 < src.length && '{}#'.contains(src[_i + 1])) {
      final end = src.indexOf("'", _i + 1);
      final text = src.substring(_i + 1, end < 0 ? src.length : end);
      _i = end < 0 ? src.length : end + 1;
      return text;
    }
    _i++;
    return "'";
  }

  void _skipSpace() {
    while (_i < src.length && src[_i].trim().isEmpty) {
      _i++;
    }
  }

  String _word() {
    _skipSpace();
    final start = _i;
    while (_i < src.length && !',{}'.contains(src[_i]) && src[_i].trim().isNotEmpty) {
      _i++;
    }
    return src.substring(start, _i);
  }

  String _argument() {
    _i++; // {
    final name = _word();
    _skipSpace();
    if (_i < src.length && src[_i] == '}') {
      _i++;
      final v = args[name];
      if (v == null) return '{$name}';
      return v is num ? _formatNumber(v) : '$v';
    }
    _i++; // ,
    final type = _word();
    _skipSpace();
    if (_i < src.length && src[_i] == '}') {
      // {n, number} etc.
      _i++;
      final v = args[name];
      return v is num ? _formatNumber(v) : '${v ?? ''}';
    }
    _i++; // ,
    if (type == 'date' || type == 'time' || type == 'number') {
      // {d, date, long} / {t, time, short} / {n, number, integer}
      final end = src.indexOf('}', _i);
      final style = src.substring(_i, end < 0 ? src.length : end).trim();
      _i = end < 0 ? src.length : end + 1;
      return _formatStyled(args[name], type, style);
    }
    final positions = <String, int>{};
    var offset = 0;
    while (true) {
      _skipSpace();
      if (_i >= src.length || src[_i] == '}') break;
      final key = _word();
      if (key.startsWith('offset:')) {
        offset = int.tryParse(key.substring(7)) ?? 0;
        continue;
      }
      _skipSpace();
      positions[key] = _i; // at '{'
      _skipBlock();
    }
    final end = _i; // at closing '}'
    final v = args[name];
    String? chosen;
    num? hash;
    if (type == 'plural' || type == 'selectordinal') {
      final n = v is num ? v : num.tryParse('$v') ?? 0;
      hash = n - offset;
      if (positions.containsKey('=$n')) {
        chosen = '=$n';
      } else {
        final cat = _pluralCategory(hash);
        chosen = positions.containsKey(cat) ? cat : 'other';
      }
    } else {
      chosen = positions.containsKey('$v') ? '$v' : 'other';
    }
    var result = '';
    final pos = positions[chosen];
    if (pos != null) {
      _i = pos + 1;
      result = _message(hash);
    }
    _i = end + 1;
    return result;
  }

  void _skipBlock() {
    // _i at '{'; move past the matching '}' honoring quotes.
    var depth = 0;
    while (_i < src.length) {
      final c = src[_i];
      if (c == "'" && _i + 1 < src.length && '{}'.contains(src[_i + 1])) {
        final endQ = src.indexOf("'", _i + 1);
        _i = endQ < 0 ? src.length : endQ + 1;
        continue;
      }
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth == 0) {
          _i++;
          return;
        }
      }
      _i++;
    }
  }

  String _pluralCategory(num n) {
    try {
      return Intl.pluralLogic(n,
          locale: locale,
          zero: 'zero',
          one: 'one',
          two: 'two',
          few: 'few',
          many: 'many',
          other: 'other');
    } catch (_) {
      return n == 1 ? 'one' : 'other';
    }
  }

  String _formatStyled(Object? v, String type, String style) {
    if (type == 'number') return v is num ? _formatNumber(v) : '${v ?? ''}';
    final d = v is DateTime ? v : DateTime.tryParse('${v ?? ''}');
    if (d == null) return '${v ?? ''}';
    try {
      if (type == 'time') return DateFormat.jm(locale).format(d);
      return switch (style) {
        'short' => DateFormat.yMd(locale),
        'full' => DateFormat.yMMMMEEEEd(locale),
        'long' => DateFormat.yMMMMd(locale),
        _ => DateFormat.yMMMd(locale),
      }.format(d);
    } catch (_) {
      return d.toIso8601String();
    }
  }

  String _formatNumber(num n) {
    try {
      return NumberFormat.decimalPattern(locale).format(n);
    } catch (_) {
      return '$n';
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';

import 'api.dart';
import 'app_dirs.dart';
import 'i18n.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'session.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await migrateLegacyDirs();
  await settings.load();
  await i18n.load(settings.language);
  settings.addListener(() {
    if (settings.language != i18n.code) i18n.load(settings.language);
  });
  // Room for a few screens of thumbnails plus full previews.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 512 << 20;
  PaintingBinding.instance.imageCache.maximumSize = 3000;
  // Release builds show a grey box for build errors; show the message instead.
  ErrorWidget.builder = (details) => Material(
        color: Colors.transparent,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SelectableText(
                '${details.exceptionAsString()}\n\n'
                '${(details.stack?.toString() ?? '').split('\n').take(12).join('\n')}',
                style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ),
        ),
      );
  runApp(const FotorollApp());
}

class FotorollApp extends StatefulWidget {
  const FotorollApp({super.key});

  @override
  State<FotorollApp> createState() => _FotorollAppState();
}

class _FotorollAppState extends State<FotorollApp> {
  final _store = SessionStore();
  bool _loading = true;
  ImmichApi? _api;
  String? _lastServer;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final creds = await _store.load();
    setState(() {
      _loading = false;
      _lastServer = creds?.serverUrl;
      if (creds != null) _api = _newApi(creds);
    });
  }

  ImmichApi _newApi(Credentials creds) => ImmichApi(creds)..onCredentialsChanged = _store.save;

  Future<void> _onLoggedIn(Credentials creds) async {
    await _store.save(creds);
    setState(() {
      _api = _newApi(creds);
      _lastServer = creds.serverUrl;
    });
  }

  Future<void> _logout() async {
    final api = _api;
    setState(() => _api = null);
    await _store.clear();
    await api?.logout();
    api?.close();
  }

  /// Colors of the Immich web client: blue on white, light blue on black.
  static ThemeData _theme(Brightness b) {
    final dark = b == Brightness.dark;
    var scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF4250AF),
      brightness: b,
    ).copyWith(primary: dark ? const Color(0xFFACCBFA) : const Color(0xFF4250AF));
    if (dark) {
      scheme = scheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF0E0E10),
        surfaceContainer: const Color(0xFF17171A),
        surfaceContainerHigh: const Color(0xFF212124),
        surfaceContainerHighest: const Color(0xFF2A2A2E),
        secondaryContainer: const Color(0xFF1E2433),
      );
    }
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      dividerColor: dark ? const Color(0xFF26262A) : const Color(0xFFE5E7EB),
      dividerTheme: DividerThemeData(
        color: dark ? const Color(0xFF26262A) : const Color(0xFFE5E7EB),
      ),
    );
  }

  /// Flutter's own widget strings (tooltips, dialogs) in the chosen language when available.
  static Locale _locale(String code) {
    final parts = code.split('_');
    final lang = parts.first;
    final candidate = parts.length > 1 && parts[1].length > 2
        ? Locale.fromSubtags(languageCode: lang, scriptCode: parts[1])
        : Locale(lang, parts.length > 1 ? parts[1] : null);
    final supported = kMaterialSupportedLanguages.contains(lang);
    return supported ? candidate : const Locale('en');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([i18n, settings]),
      builder: (context, _) => MaterialApp(
        title: 'Fotoroll',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: settings.themeMode,
        locale: _locale(i18n.code),
        supportedLocales: {for (final c in languageNames.keys) _locale(c)}.toList(),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: _loading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : _api == null
                ? LoginScreen(onLoggedIn: _onLoggedIn, initialServer: _lastServer)
                : HomeScreen(key: ValueKey(_api), api: _api!, onLogout: _logout),
      ),
    );
  }
}

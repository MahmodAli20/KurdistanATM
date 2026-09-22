import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/atm_repository.dart';
import 'data/firestore_status_repository.dart';
import 'data/status_repository.dart';
import 'firebase_options.dart';
import 'l10n/strings.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AtmFinderApp());
}

class AtmFinderApp extends StatefulWidget {
  const AtmFinderApp({super.key});

  @override
  State<AtmFinderApp> createState() => _AtmFinderAppState();
}

class _AtmFinderAppState extends State<AtmFinderApp> {
  static const _langKey = 'lang_v1';

  AppLang _lang = AppLang.ckb;
  Future<_Boot>? _boot;

  /// Held here rather than only inside _Boot, because the language callback
  /// lives above the FutureBuilder now.
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _boot = _load();
  }

  Future<_Boot> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;

    final saved = prefs.getString(_langKey);
    if (saved != null) {
      _lang = AppLang.values.firstWhere(
        (l) => l.name == saved,
        orElse: () => AppLang.ckb,
      );
    }
    return _Boot(
      atms: await AtmRepository.load(),
      status: await _statusRepository(prefs),
      prefs: prefs,
    );
  }

  void _setLang(AppLang lang) {
    _prefs?.setString(_langKey, lang.name);
    setState(() => _lang = lang);
  }

  /// Firestore when it is reachable, the on-device store when it is not.
  ///
  /// Shared status is a bonus, not a prerequisite: the ATM list is bundled, so
  /// a user with no connection - or a Firebase project that has not had its
  /// database created yet - still gets a working map instead of an error
  /// screen. Reports simply stay local until Firestore is available.
  Future<StatusRepository> _statusRepository(SharedPreferences prefs) async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final repository = FirestoreStatusRepository(
        firestore: FirebaseFirestore.instance,
        auth: FirebaseAuth.instance,
        prefs: prefs,
      );
      await repository.ensureSignedIn();
      return repository;
    } catch (error) {
      debugPrint('Firebase unavailable, using on-device reports: $error');
      return LocalStatusRepository(prefs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = Strings(_lang);

    // LangScope must sit ABOVE MaterialApp.
    //
    // Every bottom sheet in this app is a route pushed onto MaterialApp's
    // Navigator. Routes are siblings of `home`, not descendants of it, so a
    // LangScope placed inside `home` is invisible to them - Strings.of() then
    // falls back to the default language and sheets render in Sorani while the
    // rest of the app is in English. Hoisting it here puts the Navigator, and
    // therefore every route, inside the scope.
    return LangScope(
      strings: strings,
      onChange: _setLang,
      child: MaterialApp(
        title: 'Kurdistan ATM',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(_lang),
        darkTheme: AppTheme.dark(_lang),
        // `builder` wraps the Navigator itself, so sheets and overlays inherit
        // the text direction as well. Doing this only around `home` would
        // leave every sheet left-to-right in Sorani and Arabic.
        builder: (context, child) => Directionality(
          textDirection: strings.direction,
          child: child ?? const SizedBox.shrink(),
        ),
        home: FutureBuilder<_Boot>(
          future: _boot,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _StartupError(error: snapshot.error!);
            }
            if (!snapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final boot = snapshot.data!;
            return AppShell(
              atms: boot.atms,
              status: boot.status,
              prefs: boot.prefs,
            );
          },
        ),
      ),
    );
  }
}

class _Boot {
  const _Boot({
    required this.atms,
    required this.status,
    required this.prefs,
  });

  final AtmRepository atms;
  final StatusRepository status;
  final SharedPreferences prefs;
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              Text('$error', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

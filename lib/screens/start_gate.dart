import 'package:flutter/material.dart';

import '../config.dart';
import '../data/license_service.dart';
import '../l10n.dart';
import '../data/storage.dart';
import '../data/xtream_api.dart';
import '../widgets/brand.dart';
import 'blocked_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// Decides on launch: saved login → Home, otherwise → Login.
class StartGate extends StatefulWidget {
  const StartGate({super.key});
  @override
  State<StartGate> createState() => _StartGateState();
}

class _StartGateState extends State<StartGate> {
  /// Shown under the logo while connecting (null = just the spinner).
  String? _status;

  /// Couldn't reach any server (no internet yet / servers down): the
  /// "Try again" screen instead of the login screen, since the account is fine.
  String? _offlineError;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final u = Storage.username;
    final p = Storage.password;

    // Start reading the saved channel / movie / series lists right away,
    // while the app signs in, so the sections open at once.
    final host = Storage.host;
    if (u != null && p != null && host != null && host.isNotEmpty) {
      XtreamApi.preload(
        host: host,
        username: u,
        password: p,
        firstSection: Storage.lastSection,
        onlyFirst: Storage.weakDevice,
      );
    }

    // Ask "is this device blocked?" while we sign in (runs in parallel).
    final license = LicenseService.check(username: u ?? '', opened: true);

    Future<bool> blocked() async {
      final s = await license;
      if (!s.blocked) return false;
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => BlockedScreen(message: s.message),
            transitionDuration: Duration.zero,
          ),
        );
      }
      return true;
    }

    if (u == null || p == null) {
      if (!mounted || await blocked()) return;
      _toLogin(null, u);
      return;
    }
    await _signIn(u, p, blocked);
  }

  /// Signs in with the saved account. Wrong password / ended subscription
  /// -> login screen. No answer (the TV's Wi-Fi isn't connected yet, or the
  /// servers are slow) -> keeps trying for about 30 s, then "Try again".
  Future<void> _signIn(String u, String p, Future<bool> Function() blocked) async {
    if (mounted) {
      setState(() {
        _offlineError = null;
        _status = null;
      });
    }
    final started = DateTime.now();
    Object? lastError;
    for (var attempt = 0;; attempt++) {
      try {
        final (api, account) = await XtreamApi.signIn(u, p, savedHost: Storage.host);
        await Storage.setHost(api.host);
        Session.api = api;
        Session.account = account;
        XtreamApi.markSignedIn();
        if (!mounted || await blocked()) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(pageBuilder: (_, __, ___) => const HomeScreen(), transitionDuration: Duration.zero),
        );
        return;
      } on XtreamAuthException catch (e) {
        if (!mounted || await blocked()) return;
        _toLogin(e.toString(), u);
        return;
      } catch (e) {
        lastError = e;
      }
      if (!mounted) return;
      if (DateTime.now().difference(started) > const Duration(seconds: 30)) break;
      setState(() => _status = tr('Connecting...', 'جاري الاتصال...'));
      await Future<void>.delayed(Duration(seconds: attempt < 2 ? 2 : 4));
      if (!mounted) return;
    }
    if (!mounted || await blocked()) return;
    setState(() {
      _status = null;
      _offlineError = lastError?.toString() ??
          tr('Could not reach the server. Check your internet connection.', 'ما قدرنا نوصل للسيرفر. تأكد من الإنترنت.');
    });
  }

  void _toLogin(String? error, String? username) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => LoginScreen(initialError: error, initialUsername: username),
        transitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final offline = _offlineError;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(size: 64),
              const SizedBox(height: 28),
              if (offline == null) ...[
                const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
                if (_status != null) ...[
                  const SizedBox(height: 16),
                  Text(_status!, style: const TextStyle(color: AppConfig.textSecondary)),
                ],
              ] else ...[
                const Icon(Icons.wifi_off_rounded, size: 40, color: AppConfig.textSecondary),
                const SizedBox(height: 12),
                Text(
                  offline,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      autofocus: true,
                      onPressed: () => _signIn(Storage.username ?? '', Storage.password ?? '', () async => false),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(tr('Try again', 'إعادة المحاولة')),
                    ),
                    const SizedBox(width: 14),
                    OutlinedButton(
                      onPressed: () => _toLogin(null, Storage.username),
                      style: ButtonStyle(
                        side: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.focused)
                            ? const BorderSide(color: AppConfig.textPrimary, width: 2.5)
                            : const BorderSide(color: AppConfig.divider)),
                      ),
                      child: Text(tr('Sign in with another account', 'تسجيل الدخول بحساب آخر')),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

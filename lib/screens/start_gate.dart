import 'package:flutter/material.dart';

import '../config.dart';
import '../data/license_service.dart';
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
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final u = Storage.username;
    final p = Storage.password;
    String? error;

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

    if (u != null && p != null) {
      final api = XtreamApi(host: AppConfig.host, username: u, password: p);
      try {
        final account = await api.login();
        Session.api = api;
        Session.account = account;
        if (!mounted || await blocked()) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(pageBuilder: (_, __, ___) => const HomeScreen(), transitionDuration: Duration.zero),
        );
        return;
      } catch (e) {
        error = e.toString();
      }
    }

    if (!mounted || await blocked()) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => LoginScreen(initialError: error, initialUsername: u),
        transitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandMark(size: 64),
            SizedBox(height: 28),
            SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
          ],
        ),
      ),
    );
  }
}

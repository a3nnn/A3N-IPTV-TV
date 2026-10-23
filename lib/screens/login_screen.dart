import 'package:flutter/material.dart';

import '../config.dart';
import '../data/license_service.dart';
import '../data/storage.dart';
import '../data/xtream_api.dart';
import '../utils.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import 'blocked_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  final String? initialError;
  final String? initialUsername;
  const LoginScreen({super.key, this.initialError, this.initialUsername});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _user = TextEditingController(text: widget.initialUsername ?? '');
  final TextEditingController _pass = TextEditingController();
  final FocusNode _passFocus = FocusNode();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.initialError;
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final u = _user.text.trim();
    final p = _pass.text.trim();
    if (u.isEmpty || p.isEmpty) {
      setState(() => _error = 'Enter your username and password.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    final api = XtreamApi(host: AppConfig.host, username: u, password: p);
    try {
      final account = await api.login();
      await Storage.saveCredentials(u, p);
      Session.api = api;
      Session.account = account;
      final license = await LicenseService.check(username: u);
      if (!mounted) return;
      if (license.blocked) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => BlockedScreen(message: license.message)),
        );
        return;
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned(top: 18, left: 18, child: SignatureBadge()),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.6, -0.8),
                  radius: 1.4,
                  colors: [fade(AppConfig.primary, 0.12), AppConfig.background],
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: Container(
                width: 420,
                padding: const EdgeInsets.fromLTRB(36, 40, 36, 32),
                decoration: BoxDecoration(
                  color: AppConfig.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppConfig.divider),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandMark(size: 52)),
                    const SizedBox(height: 34),
                    TextField(
                      controller: _user,
                      autofocus: true,
                      enabled: !_loading,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _passFocus.requestFocus(),
                      decoration: const InputDecoration(
                        hintText: 'Username',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _pass,
                      focusNode: _passFocus,
                      enabled: !_loading,
                      obscureText: _obscure,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        hintText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, style: const TextStyle(color: AppConfig.danger, fontSize: 13)),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                              )
                            : const Text('Sign in'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

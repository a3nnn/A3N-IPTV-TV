import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../data/license_service.dart';
import '../data/storage.dart';
import '../data/xtream_api.dart';
import '../utils.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import 'blocked_screen.dart';
import 'home_screen.dart';
import '../l10n.dart';

class LoginScreen extends StatefulWidget {
  final String? initialError;
  final String? initialUsername;
  const LoginScreen({super.key, this.initialError, this.initialUsername});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _user = TextEditingController(text: widget.initialUsername ?? '');
  // Filled in when the account is still saved (e.g. the server couldn't be
  // reached at start): OK on "Sign in" is enough.
  late final TextEditingController _pass = TextEditingController(text: Storage.password ?? '');
  final FocusNode _userBox = FocusNode();
  final FocusNode _passBox = FocusNode();
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
    _userBox.dispose();
    _passBox.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final u = _user.text.trim();
    final p = _pass.text.trim();
    if (u.isEmpty || p.isEmpty) {
      setState(() => _error = tr('Enter your username and password.', 'اكتب اسم المستخدم وكلمة المرور.'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final (api, account) = await XtreamApi.signIn(u, p);
      await Storage.saveCredentials(u, p);
      await Storage.setHost(api.host);
      Session.api = api;
      Session.account = account;
      XtreamApi.markSignedIn();
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
                    _RemoteField(
                      box: _userBox,
                      autofocus: _user.text.trim().isEmpty || _pass.text.trim().isEmpty,
                      onSubmitted: () => _passBox.requestFocus(),
                      builder: (fieldNode) => TextField(
                        controller: _user,
                        focusNode: fieldNode,
                        enabled: !_loading,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _passBox.requestFocus(),
                        decoration: InputDecoration(
                          hintText: tr('Username', 'اسم المستخدم'),
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _RemoteField(
                      box: _passBox,
                      onSubmitted: _submit,
                      builder: (fieldNode) => TextField(
                        controller: _pass,
                        focusNode: fieldNode,
                        enabled: !_loading,
                        obscureText: _obscure,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          hintText: tr('Password', 'كلمة المرور'),
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: ExcludeFocus(
                            child: IconButton(
                              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
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
                        autofocus: _user.text.trim().isNotEmpty && _pass.text.trim().isNotEmpty,
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                              )
                            : Text(tr('Sign in', 'تسجيل الدخول')),
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


/// A text box for the TV remote: the remote lands on the box without
/// opening the keyboard; OK opens the keyboard to type; ▲ ▼ always leave
/// the box (even if a TV's keyboard doesn't take the remote's arrows).
class _RemoteField extends StatefulWidget {
  final FocusNode box;
  final bool autofocus;
  final VoidCallback onSubmitted;
  final Widget Function(FocusNode fieldNode) builder;
  const _RemoteField({required this.box, required this.onSubmitted, required this.builder, this.autofocus = false});

  @override
  State<_RemoteField> createState() => _RemoteFieldState();
}

class _RemoteFieldState extends State<_RemoteField> {
  late final FocusNode _field = FocusNode(canRequestFocus: false, onKeyEvent: _fieldKeys);
  bool _boxFocused = false;

  @override
  void initState() {
    super.initState();
    _field.addListener(() {
      // Typing finished (keyboard closed / focus moved): back to a plain box.
      if (!_field.hasFocus && _field.canRequestFocus) {
        _field.canRequestFocus = false;
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _edit() {
    _field.canRequestFocus = true;
    _field.requestFocus();
    setState(() {});
  }

  void _leave(TraversalDirection dir) {
    widget.box.requestFocus();
    _field.canRequestFocus = false;
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.box.focusInDirection(dir));
  }

  KeyEventResult _fieldKeys(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      _leave(TraversalDirection.down);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      _leave(TraversalDirection.up);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.numpadEnter) {
      _leave(TraversalDirection.down);
      widget.onSubmitted();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _boxKeys(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _edit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.box,
      autofocus: widget.autofocus,
      onKeyEvent: _boxKeys,
      onFocusChange: (f) => setState(() => _boxFocused = f),
      child: GestureDetector(
        onTap: _edit,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _boxFocused ? AppConfig.textPrimary : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: widget.builder(_field),
        ),
      ),
    );
  }
}

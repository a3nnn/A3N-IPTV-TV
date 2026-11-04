import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../l10n.dart';
import '../data/storage.dart';
import '../data/xtream_api.dart';
import '../player/player_service.dart';
import '../utils.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/sub_style.dart';
import '../widgets/update_dialog.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import '../text_size.dart';

class SettingsSection extends StatefulWidget {
  const SettingsSection({super.key});

  @override
  State<SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<SettingsSection> {
  bool _lite = Storage.liteMode;
  String _engine = Storage.playerEngine;
  bool _compatible = Storage.compatibleDecoder;
  bool _afr = Storage.matchFrameRate;
  String _subLang = Storage.subtitleLang;
  String _textSize = TextSize.value.value;

  void _setSubLang(String v) {
    setState(() => _subLang = v);
    Storage.setSubtitleLang(v);
  }

  Future<void> _setLanguage(bool arabic) async {
    if (arabic == L.isAr) return;
    await PlayerService.instance.stop();
    HomeScreen.openSettingsNext = true; // come back to this page
    await L.setArabic(arabic); // the whole app redraws in the new language
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConfig.surface,
        title: Text(tr('Sign out?', 'تسجيل الخروج؟')),
        content: Text(tr('You will need to enter your username and password again.', 'بتحتاج تكتب اسم المستخدم وكلمة المرور مرة ثانية.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel', 'إلغاء'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Sign out', 'تسجيل الخروج'))),
        ],
      ),
    );
    if (ok != true) return;
    await PlayerService.instance.stop();
    await Storage.clearCredentials();
    Session.api = null;
    Session.account = null;
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  // ------------------------------------------------------------ layout
  // Two columns: the groups (▲ ▼ to move between them) and the settings of
  // the group in focus. Every setting is one line showing its value; OK on
  // a choice opens a small window to pick another.

  int _group = 0;
  final List<FocusNode> _groupNodes = List.generate(6, (_) => FocusNode());

  @override
  void dispose() {
    for (final n in _groupNodes) {
      n.dispose();
    }
    super.dispose();
  }

  List<(IconData, String)> get _groups => [
        (Icons.tune_rounded, tr('Display', 'العرض')),
        (Icons.play_circle_outline_rounded, tr('Playback', 'التشغيل')),
        (Icons.closed_caption_outlined, tr('Subtitles', 'الترجمة')),
        (Icons.person_outline_rounded, tr('Account', 'الحساب')),
        (Icons.settings_remote_outlined, tr('Remote control', 'الريموت')),
        (Icons.info_outline_rounded, tr('About', 'عن التطبيق')),
      ];

  void _selectGroup(int i) {
    if (i < 0 || i >= _groupNodes.length) return;
    setState(() => _group = i);
    _groupNodes[i].requestFocus();
  }

  /// ▲ ▼ inside the group list change the group (and never leave the list).
  KeyEventResult _groupKeys(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      _selectGroup((_group + 1).clamp(0, _groupNodes.length - 1));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      _selectGroup((_group - 1).clamp(0, _groupNodes.length - 1));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _restartHint() {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(tr('Close and reopen the app to apply.', 'اقفل التطبيق وافتحه عشان يتطبق التغيير.'))),
    );
  }

  Future<void> _choose<T>({
    required String title,
    required T current,
    required List<(T, String)> options,
    required ValueChanged<T> onPick,
  }) async {
    final picked = await showDialog<T>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConfig.surface,
        title: Text(title),
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final o in options)
                _LangOption(
                  label: o.$2,
                  selected: o.$1 == current,
                  autofocus: o.$1 == current,
                  onTap: () => Navigator.pop(ctx, o.$1),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && picked != current) onPick(picked);
  }

  String _labelOf<T>(T v, List<(T, String)> options) =>
      options.firstWhere((o) => o.$1 == v, orElse: () => options.first).$2;

  // ------------------------------------------------------------ groups

  List<Widget> _display() {
    final langs = [(true, 'العربية'), (false, 'English')];
    final sizes = [
      ('small', tr('Small', 'صغير')),
      ('normal', tr('Normal (recommended)', 'عادي (الأنسب)')),
      ('large', tr('Large', 'كبير')),
    ];
    return [
      _ChoiceRow(
        title: tr('Language', 'اللغة'),
        value: _labelOf(L.isAr, langs),
        onTap: () => _choose<bool>(
          title: tr('Language', 'اللغة'),
          current: L.isAr,
          options: langs,
          onPick: _setLanguage,
        ),
      ),
      _ChoiceRow(
        title: tr('Text size', 'حجم الخط'),
        value: _labelOf(_textSize, sizes),
        onTap: () => _choose<String>(
          title: tr('Text size', 'حجم الخط'),
          current: _textSize,
          options: sizes,
          onPick: (v) {
            setState(() => _textSize = v);
            TextSize.set(v);
          },
        ),
      ),
      // Needs the frame rate of the video: main player only.
      if (_engine != 'exo')
        _SwitchRow(
          title: tr('Match screen refresh rate (movies & series)', 'مطابقة معدل الشاشة (الأفلام والمسلسلات)'),
          subtitle: tr('Smoother motion: the TV switches to the rate of the video (e.g. 50 Hz) while it plays. The screen goes black for a second when it switches, that is normal.',
              'حركة أنعم: التلفزيون يتحوّل لمعدل الفيديو (مثل 50 هيرتز) وقت التشغيل. الشاشة تسوّد ثانية وقت التحويل، وهذا طبيعي.'),
          value: _afr,
          onChanged: (v) {
            setState(() => _afr = v);
            Storage.setMatchFrameRate(v);
          },
        ),
    ];
  }

  List<Widget> _playback() {
    final engines = [
      ('mpv', tr('Main player', 'المشغّل الأساسي')),
      ('exo', tr('Weak-device player', 'مشغّل الأجهزة الضعيفة')),
    ];
    return [
      _ChoiceRow(
        title: tr('Video player', 'مشغّل الفيديو'),
        subtitle: tr('If video stutters or is slow on your device, try the weak-device player (no audio / subtitle choice). Reopen the app after changing.',
            'إذا الفيديو يقطّع أو بطيء على جهازك، جرّب مشغّل الأجهزة الضعيفة (بدون اختيار الصوت والترجمة). اقفل التطبيق وافتحه بعد التغيير.'),
        value: _labelOf(_engine, engines),
        onTap: () => _choose<String>(
          title: tr('Video player', 'مشغّل الفيديو'),
          current: _engine,
          options: engines,
          onPick: (v) {
            setState(() => _engine = v);
            Storage.setPlayerEngine(v);
            _restartHint();
          },
        ),
      ),
      _SwitchRow(
        title: tr('Light mode (weak devices)', 'الوضع الخفيف (للأجهزة الضعيفة)'),
        subtitle: tr('If the app is heavy, freezes or is slow on your device: no preview while browsing, no animations, smaller pictures, lighter player. Reopen the app after changing.',
            'إذا التطبيق ثقيل أو يعلّق أو بطيء على جهازك: بدون معاينة أثناء التصفح، بدون حركات، صور أصغر، ومشغّل أخف. اقفل التطبيق وافتحه بعد التغيير.'),
        value: _lite,
        onChanged: (v) {
          setState(() => _lite = v);
          Storage.setLiteMode(v);
          _restartHint();
        },
      ),
      if (_engine != 'exo')
        _SwitchRow(
          title: tr('Compatible video mode', 'وضع الفيديو المتوافق'),
          subtitle: tr('Only if channels show a black picture or no video. Reopen the app after changing.',
              'استخدمه بس إذا الصورة سوداء أو ما يطلع فيديو. اقفل التطبيق وافتحه بعد التغيير.'),
          value: _compatible,
          onChanged: (v) {
            setState(() => _compatible = v);
            Storage.setCompatibleDecoder(v);
            _restartHint();
          },
        ),
    ];
  }

  List<Widget> _subtitles() {
    final langs = [
      ('off', tr('No subtitles', 'بدون ترجمة')),
      ('ar', tr('Arabic', 'العربية')),
      ('en', tr('English', 'الإنجليزية')),
      ('ar_en', tr('Arabic, otherwise English', 'العربية، وإذا ما فيه فالإنجليزية')),
    ];
    return [
      _ChoiceRow(
        title: tr('Subtitles for movies & series', 'ترجمة الأفلام والمسلسلات'),
        subtitle: tr('Chosen automatically when a movie or episode starts (if the file has it).',
            'تنختار تلقائياً أول ما يبدأ الفلم أو الحلقة (إذا كانت موجودة في الملف).'),
        value: _labelOf(_subLang, langs),
        onTap: () => _choose<String>(
          title: tr('Subtitles for movies & series', 'ترجمة الأفلام والمسلسلات'),
          current: _subLang,
          options: langs,
          onPick: _setSubLang,
        ),
      ),
      const SizedBox(height: 18),
      _SubHeader(tr('Subtitle style', 'شكل الترجمة')),
      const SubStylePicker(),
    ];
  }

  List<Widget> _account() {
    final acc = Session.account;
    final user = acc?.username.isNotEmpty == true ? acc!.username : (Storage.username ?? '-');
    return [
      _InfoRow(tr('Username', 'اسم المستخدم'), user),
      _InfoRow(tr('Status', 'الحالة'), acc?.status.isNotEmpty == true ? acc!.status : '-'),
      _InfoRow(tr('Expires', 'ينتهي'), acc?.expDate != null ? fmtDate(acc!.expDate!) : tr('Unlimited', 'غير محدود')),
      if (acc != null && acc.maxConnections > 0)
        _InfoRow(tr('Connections', 'الاتصالات'), '${acc.activeConnections} / ${acc.maxConnections}'),
      _InfoRow(tr('Device ID', 'رقم الجهاز'), Storage.deviceId),
      const SizedBox(height: 18),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          onPressed: () => _logout(context),
          icon: const Icon(Icons.logout_rounded, color: AppConfig.danger),
          label: Text(tr('Sign out', 'تسجيل الخروج'), style: const TextStyle(color: AppConfig.danger)),
          style: ButtonStyle(
            side: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.focused)
                ? const BorderSide(color: AppConfig.textPrimary, width: 2.5)
                : const BorderSide(color: AppConfig.danger)),
          ),
        ),
      ),
    ];
  }

  List<Widget> _remote() => [
        _InfoRow(tr('Play a channel', 'تشغيل قناة'), tr('OK on a channel (press OK again for full screen)', 'OK على القناة (واضغط OK مرة ثانية لملء الشاشة)')),
        _InfoRow(tr('Change channel', 'تغيير القناة'), tr('▲ / ▼ in full screen', '▲ / ▼ في ملء الشاشة')),
        _InfoRow(tr('Show info', 'عرض المعلومات'), tr('OK in full screen', 'OK في ملء الشاشة')),
        _InfoRow(tr('Favorites / pin', 'المفضلة / التثبيت'), tr('Hold OK on a channel, poster or category', 'اضغط مطوّل على OK فوق القناة أو البوستر أو القسم')),
        _InfoRow(tr('Movies & series', 'الأفلام والمسلسلات'), tr('OK = play / pause,  ◀ ▶ = seek,  ▼ = audio & subtitles', 'OK = تشغيل / إيقاف،  ◀ ▶ = ترجيع وتقديم،  ▼ = الصوت والترجمة')),
        _InfoRow(tr('Back', 'رجوع'), tr('BACK button', 'زر الرجوع')),
      ];

  List<Widget> _about() => [
        const Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: Align(alignment: AlignmentDirectional.centerStart, child: BrandMark(size: 34)),
        ),
        _InfoRow(tr('Version', 'الإصدار'), AppConfig.version),
        const _InfoRow('', AppConfig.signature),
        const SizedBox(height: 18),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            onPressed: () => checkForUpdatesManually(context),
            icon: const Icon(Icons.system_update_rounded),
            label: Text(tr('Check for updates', 'البحث عن تحديث')),
          ),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    final content = switch (_group) {
      0 => _display(),
      1 => _playback(),
      2 => _subtitles(),
      3 => _account(),
      4 => _remote(),
      _ => _about(),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Groups
        Container(
          width: 250,
          color: AppConfig.surface,
          padding: const EdgeInsets.fromLTRB(14, 24, 14, 16),
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _groupKeys,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 10, bottom: 18),
                  child: Text(tr('Settings', 'الإعدادات'),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                ),
                for (var i = 0; i < groups.length; i++)
                  _GroupTile(
                    icon: groups[i].$1,
                    label: groups[i].$2,
                    selected: i == _group,
                    focusNode: _groupNodes[i],
                    autofocus: i == _group,
                    onTap: () => _selectGroup(i),
                    // Coming back from the settings column (or the menu):
                    // land on the group that is open, not the nearest one.
                    onFocused: () {
                      if (i != _group) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _groupNodes[_group].requestFocus();
                        });
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        // Settings of the open group
        Expanded(
          child: FocusTraversalGroup(
            child: ListView(
              key: ValueKey(_group),
              padding: const EdgeInsets.fromLTRB(36, 30, 36, 30),
              children: [
                Text(groups[_group].$2, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 18),
                Container(
                  constraints: const BoxConstraints(maxWidth: 760),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppConfig.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppConfig.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: content,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ pieces

class _GroupTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool autofocus;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback onFocused;
  const _GroupTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.focusNode,
    required this.onTap,
    required this.onFocused,
    this.autofocus = false,
  });

  @override
  State<_GroupTile> createState() => _GroupTileState();
}

class _GroupTileState extends State<_GroupTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.selected;
    final color = _focused || on ? AppConfig.primary : AppConfig.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: _focused
            ? fade(AppConfig.primary, 0.22)
            : (on ? AppConfig.surfaceHigh : Colors.transparent),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          focusColor: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          onFocusChange: (f) {
            setState(() => _focused = f);
            if (f) widget.onFocused();
          },
          onTap: widget.onTap,
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _focused ? AppConfig.textPrimary : Colors.transparent, width: 2.5),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 24, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 17, fontWeight: on ? FontWeight.w700 : FontWeight.w600, color: color)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One setting on one line: name (and a short help line) with its value;
/// OK opens the choices.
class _ChoiceRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String value;
  final VoidCallback onTap;
  const _ChoiceRow({required this.title, required this.value, required this.onTap, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return FocusRing(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppConfig.textSecondary)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppConfig.primary)),
            ),
            const SizedBox(width: 6),
            Icon(Directionality.of(context) == TextDirection.rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                color: AppConfig.textSecondary),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _SubHeader extends StatelessWidget {
  final String text;
  const _SubHeader(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 10, bottom: 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({required this.title, required this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return FocusRing(
      child: SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppConfig.textSecondary)),
      value: value,
      onChanged: onChanged,
    ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 170, child: Text(label, style: const TextStyle(color: AppConfig.textSecondary))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

class _LangOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool autofocus;
  const _LangOption({required this.label, required this.selected, required this.onTap, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    return FocusRing(
      child: ListTile(
      dense: true,
      autofocus: autofocus,
      selected: selected,
      selectedColor: AppConfig.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: 22),
      title: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      onTap: onTap,
    ),
    );
  }
}

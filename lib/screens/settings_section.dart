import 'package:flutter/material.dart';

import '../config.dart';
import '../l10n.dart';
import '../data/storage.dart';
import '../data/xtream_api.dart';
import '../player/player_service.dart';
import '../utils.dart';
import '../widgets/brand.dart';
import '../widgets/update_dialog.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SettingsSection extends StatefulWidget {
  const SettingsSection({super.key});

  @override
  State<SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<SettingsSection> {
  bool _preview = Storage.previewEnabled;
  bool _compatible = Storage.compatibleDecoder;

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

  @override
  Widget build(BuildContext context) {
    final acc = Session.account;
    final user = acc?.username.isNotEmpty == true ? acc!.username : (Storage.username ?? '-');

    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Text(tr('Settings', 'الإعدادات'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 24),
        _Card(
          title: tr('Language', 'اللغة'),
          children: [
            _LangOption(label: 'العربية', selected: L.isAr, onTap: () => _setLanguage(true)),
            _LangOption(label: 'English', selected: !L.isAr, onTap: () => _setLanguage(false)),
          ],
        ),
        const SizedBox(height: 20),
        _Card(
          title: tr('Account', 'الحساب'),
          children: [
            _InfoRow(tr('Username', 'اسم المستخدم'), user),
            _InfoRow(tr('Status', 'الحالة'), acc?.status.isNotEmpty == true ? acc!.status : '-'),
            _InfoRow(tr('Expires', 'ينتهي'), acc?.expDate != null ? fmtDate(acc!.expDate!) : tr('Unlimited', 'غير محدود')),
            if (acc != null && acc.maxConnections > 0)
              _InfoRow(tr('Connections', 'الاتصالات'), '${acc.activeConnections} / ${acc.maxConnections}'),
            _InfoRow(tr('Device ID', 'رقم الجهاز'), Storage.deviceId),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () => _logout(context),
                icon: const Icon(Icons.logout_rounded, color: AppConfig.danger),
                label: Text(tr('Sign out', 'تسجيل الخروج'), style: const TextStyle(color: AppConfig.danger)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppConfig.danger)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _Card(
          title: tr('Playback', 'التشغيل'),
          children: [
            _SwitchRow(
              title: tr('Preview video while browsing', 'معاينة الفيديو أثناء التصفح'),
              subtitle: tr('Off = lighter: OK on a channel opens it full screen directly', 'إذا طفيته يصير أخف: OK على القناة يفتحها بملء الشاشة على طول'),
              value: _preview,
              onChanged: (v) {
                setState(() => _preview = v);
                Storage.setPreviewEnabled(v);
              },
            ),
            _SwitchRow(
              title: tr('Compatible video mode', 'وضع الفيديو المتوافق'),
              subtitle: tr('Only if channels show a black picture or no video. Restart the app after changing.', 'استخدمه بس إذا الصورة سوداء أو ما يطلع فيديو. اقفل التطبيق وافتحه بعد التغيير.'),
              value: _compatible,
              onChanged: (v) {
                setState(() => _compatible = v);
                Storage.setCompatibleDecoder(v);
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  SnackBar(content: Text(tr('Close and reopen the app to apply.', 'اقفل التطبيق وافتحه عشان يتطبق التغيير.'))),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        _Card(
          focusable: true,
          title: tr('Remote control', 'الريموت'),
          children: [
            _InfoRow(tr('Play a channel', 'تشغيل قناة'), tr('OK on a channel (press OK again for full screen)', 'OK على القناة (واضغط OK مرة ثانية لملء الشاشة)')),
            _InfoRow(tr('Change channel', 'تغيير القناة'), tr('▲ / ▼ in full screen', '▲ / ▼ في ملء الشاشة')),
            _InfoRow(tr('Show info', 'عرض المعلومات'), tr('OK in full screen', 'OK في ملء الشاشة')),
            _InfoRow(tr('Favorites / pin', 'المفضلة / التثبيت'), tr('Hold OK on a channel, poster or category', 'اضغط مطوّل على OK فوق القناة أو البوستر أو القسم')),
            _InfoRow(tr('Movies & series', 'الأفلام والمسلسلات'), tr('OK = play / pause,  ◀ ▶ = seek,  ▼ = audio & subtitles', 'OK = تشغيل / إيقاف،  ◀ ▶ = ترجيع وتقديم،  ▼ = الصوت والترجمة')),
            _InfoRow(tr('Back', 'رجوع'), tr('BACK button', 'زر الرجوع')),
          ],
        ),
        const SizedBox(height: 20),
        _Card(
          title: tr('About', 'عن التطبيق'),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Align(alignment: AlignmentDirectional.centerStart, child: BrandMark(size: 34)),
            ),
            _InfoRow(tr('Version', 'الإصدار'), AppConfig.version),
            const _InfoRow('', AppConfig.signature),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                onPressed: () => checkForUpdatesManually(context),
                icon: const Icon(Icons.system_update_rounded),
                label: Text(tr('Check for updates', 'البحث عن تحديث')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Card extends StatefulWidget {
  final String title;
  final List<Widget> children;
  /// Cards with only text get focus themselves, so the remote can scroll to them.
  final bool focusable;
  const _Card({required this.title, required this.children, this.focusable = false});

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      constraints: const BoxConstraints(maxWidth: 720),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppConfig.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _focused ? AppConfig.textPrimary : AppConfig.divider,
          width: _focused ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title.toUpperCase(),
              style: TextStyle(
                  fontSize: 12, letterSpacing: L.spacing(1.3), color: AppConfig.textSecondary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ...widget.children,
        ],
      ),
    );
    if (!widget.focusable) return card;
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      child: card,
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({required this.title, required this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppConfig.textSecondary)),
      value: value,
      onChanged: onChanged,
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
  const _LangOption({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      selected: selected,
      selectedColor: AppConfig.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: 22),
      title: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}

import 'package:flutter/material.dart';

import '../config.dart';
import '../data/storage.dart';
import '../data/xtream_api.dart';
import '../player/player_service.dart';
import '../utils.dart';
import '../widgets/brand.dart';
import '../widgets/update_dialog.dart';
import 'login_screen.dart';

class SettingsSection extends StatefulWidget {
  const SettingsSection({super.key});

  @override
  State<SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<SettingsSection> {
  bool _preview = Storage.previewEnabled;
  bool _compatible = Storage.compatibleDecoder;

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConfig.surface,
        title: const Text('Sign out?'),
        content: const Text('You will need to enter your username and password again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
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
        const Text('Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 24),
        _Card(
          title: 'Account',
          children: [
            _InfoRow('Username', user),
            _InfoRow('Status', acc?.status.isNotEmpty == true ? acc!.status : '-'),
            _InfoRow('Expires', acc?.expDate != null ? fmtDate(acc!.expDate!) : 'Unlimited'),
            if (acc != null && acc.maxConnections > 0)
              _InfoRow('Connections', '${acc.activeConnections} / ${acc.maxConnections}'),
            _InfoRow('Device ID', Storage.deviceId),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _logout(context),
                icon: const Icon(Icons.logout_rounded, color: AppConfig.danger),
                label: const Text('Sign out', style: TextStyle(color: AppConfig.danger)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppConfig.danger)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _Card(
          title: 'Playback',
          children: [
            _SwitchRow(
              title: 'Preview video while browsing',
              subtitle: 'Off = lighter: OK on a channel opens it full screen directly',
              value: _preview,
              onChanged: (v) {
                setState(() => _preview = v);
                Storage.setPreviewEnabled(v);
              },
            ),
            _SwitchRow(
              title: 'Compatible video mode',
              subtitle: 'Only if channels show a black picture or no video. Restart the app after changing.',
              value: _compatible,
              onChanged: (v) {
                setState(() => _compatible = v);
                Storage.setCompatibleDecoder(v);
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(content: Text('Close and reopen the app to apply.')),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _Card(
          focusable: true,
          title: 'Remote control',
          children: [
            _InfoRow('Play a channel', 'OK on a channel (press OK again for full screen)'),
            _InfoRow('Change channel', '▲ / ▼ in full screen'),
            _InfoRow('Show info', 'OK in full screen'),
            _InfoRow('Movies & series', 'OK = play / pause,  ◀ ▶ = seek'),
            _InfoRow('Back', 'BACK button'),
          ],
        ),
        const SizedBox(height: 20),
        _Card(
          title: 'About',
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Align(alignment: Alignment.centerLeft, child: BrandMark(size: 34)),
            ),
            const _InfoRow('Version', AppConfig.version),
            const _InfoRow('', AppConfig.signature),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => checkForUpdatesManually(context),
                icon: const Icon(Icons.system_update_rounded),
                label: const Text('Check for updates'),
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
              style: const TextStyle(
                  fontSize: 12, letterSpacing: 1.3, color: AppConfig.textSecondary, fontWeight: FontWeight.w700)),
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

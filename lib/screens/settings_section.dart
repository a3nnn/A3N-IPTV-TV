import 'package:flutter/material.dart';

import '../config.dart';
import '../data/storage.dart';
import '../data/xtream_api.dart';
import '../player/player_service.dart';
import '../utils.dart';
import '../widgets/brand.dart';
import 'login_screen.dart';

class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key});

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
        const _Card(
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
          ],
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Card({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 720),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppConfig.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppConfig.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(
                  fontSize: 12, letterSpacing: 1.3, color: AppConfig.textSecondary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ...children,
        ],
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

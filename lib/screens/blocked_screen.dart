import 'package:flutter/material.dart';

import '../config.dart';
import '../data/license_service.dart';
import '../data/storage.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import 'start_gate.dart';
import '../l10n.dart';

/// Shown when you block this device or username from Supabase.
class BlockedScreen extends StatefulWidget {
  final String? message;
  const BlockedScreen({super.key, this.message});

  @override
  State<BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<BlockedScreen> {
  bool _checking = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _message = widget.message;
  }

  Future<void> _retry() async {
    setState(() => _checking = true);
    final status = await LicenseService.check(username: Storage.username ?? '');
    if (!mounted) return;
    if (!status.blocked) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const StartGate()),
        (_) => false,
      );
      return;
    }
    setState(() {
      _checking = false;
      _message = status.message;
    });
  }

  /// The title, by the reason sent from Supabase (A3N Manager).
  static String _title() => switch (Storage.licenseReason) {
        'locked' => tr('This account is for another device.', 'هذا الحساب مخصص لجهاز آخر.'),
        'limit' => tr('This account is already used on the most devices allowed.', 'هذا الحساب وصل للحد الأعلى من الأجهزة.'),
        'username' => tr('This account has been disabled.', 'تم إيقاف هذا الحساب.'),
        _ => tr('This app has been disabled on this device.', 'تم إيقاف التطبيق على هذا الجهاز.'),
      };

  @override
  Widget build(BuildContext context) {
    final msg = (_message ?? '').trim();
    return Scaffold(
      body: Stack(
        children: [
          const Positioned(top: 18, left: 18, child: SignatureBadge()),
          Center(
            child: Container(
              width: 460,
              padding: const EdgeInsets.fromLTRB(36, 40, 36, 32),
              decoration: BoxDecoration(
                color: AppConfig.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppConfig.divider),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandMark(size: 40),
                  const SizedBox(height: 28),
                  const Icon(Icons.block_rounded, color: AppConfig.danger, size: 40),
                  const SizedBox(height: 14),
                  Text(
                    _title(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  if (msg.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      msg,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppConfig.textSecondary, height: 1.5),
                    ),
                  ],
                  const SizedBox(height: 26),
                  SizedBox(
                    height: 44,
                    child: FilledButton.icon(
                      onPressed: _checking ? null : _retry,
                      icon: _checking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: Text(tr('Check again', 'تحقق مرة ثانية')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

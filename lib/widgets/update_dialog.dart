import 'package:flutter/material.dart';

import '../config.dart';
import '../data/update_service.dart';
import '../utils.dart';

/// Optional update: "Later" closes, "Update" downloads and opens the installer.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(info: info),
  );
}

/// Used by the "Check for updates" button in Settings.
Future<void> checkForUpdatesManually(BuildContext context) async {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.showSnackBar(const SnackBar(content: Text('Checking for updates...'), duration: Duration(seconds: 2)));
  final info = await UpdateService.check();
  if (!context.mounted) return;
  m?.hideCurrentSnackBar();
  if (info == null) {
    m?.showSnackBar(SnackBar(content: Text('You have the latest version (${AppConfig.version}).')));
    return;
  }
  await showUpdateDialog(context, info);
}

enum _Phase { ask, downloading, installing, error }

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  _Phase _phase = _Phase.ask;
  double _progress = 0;
  String? _error;

  Future<void> _update() async {
    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
      _error = null;
    });
    try {
      final file = await UpdateService.download(widget.info, (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      setState(() => _phase = _Phase.installing);
      final err = await UpdateService.install(file);
      if (!mounted) return;
      if (err == null) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _phase = _Phase.error;
          _error = err;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = 'Could not download the update. Check your internet and try again.';
      });
    }
  }

  String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';

  @override
  Widget build(BuildContext context) {
    final busy = _phase == _Phase.downloading || _phase == _Phase.installing;
    final info = widget.info;

    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        backgroundColor: AppConfig.surface,
        title: Row(
          children: [
            const Icon(Icons.system_update_rounded, color: AppConfig.primary),
            const SizedBox(width: 12),
            Text('Update available  ·  ${info.version}'),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You have ${AppConfig.version}.${info.size > 0 ? '  Download size: ${_mb(info.size)}.' : ''}',
                style: const TextStyle(color: AppConfig.textSecondary),
              ),
              if (info.notes.isNotEmpty && _phase == _Phase.ask) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: SingleChildScrollView(child: Text(info.notes, style: const TextStyle(height: 1.4))),
                ),
              ],
              if (_phase == _Phase.downloading) ...[
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _progress < 0 ? null : _progress,
                    minHeight: 6,
                    backgroundColor: fade(AppConfig.textSecondary, 0.2),
                  ),
                ),
                const SizedBox(height: 8),
                Text(_progress < 0 ? 'Downloading...' : 'Downloading...  ${(_progress * 100).toStringAsFixed(0)}%'),
              ],
              if (_phase == _Phase.installing) ...[
                const SizedBox(height: 18),
                const Text('Opening the installer... press Install on the next screen.'),
              ],
              if (_phase == _Phase.error && _error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: const TextStyle(color: AppConfig.danger, height: 1.4)),
              ],
            ],
          ),
        ),
        actions: busy
            ? const []
            : [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Later'),
                ),
                FilledButton.icon(
                  autofocus: true,
                  onPressed: _update,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(_phase == _Phase.error ? 'Try again' : 'Update'),
                ),
              ],
      ),
    );
  }
}

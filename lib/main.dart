import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'config.dart';
import 'l10n.dart';
import 'data/disk_cache.dart';
import 'data/storage.dart';
import 'data/watch_history.dart';
import 'screens/start_gate.dart';
import 'theme.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Storage.init();
  // The installed app's real version (same number as typed in release.bat).
  try {
    final info = await PackageInfo.fromPlatform();
    if (RegExp(r'^\d+\.\d+').hasMatch(info.version)) AppConfig.version = info.version;
  } catch (_) {}
  L.init();
  WatchHistory.init();
  // Saved posters / lists on the TV (doesn't hold up the start).
  DiskCache.init();

  // Keep decoded logos/posters small in memory (TVs have little RAM).
  PaintingBinding.instance.imageCache
    ..maximumSize = 250
    ..maximumSizeBytes = 40 << 20;

  // Full screen on the TV: no status or navigation bars.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const A3NApp());
}

class A3NApp extends StatelessWidget {
  const A3NApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Changing the language redraws the whole app (new key = fresh screens).
    return ValueListenableBuilder<bool>(
      valueListenable: L.arabic,
      builder: (context, arabic, _) => _app(arabic),
    );
  }

  Widget _app(bool arabic) {
    return MaterialApp(
      key: ValueKey(arabic),
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Remote: the OK / center button activates the focused item.
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.gameButtonA): const ActivateIntent(),
      },
      // Remote navigation: the focused row glides to the middle of the list.
      // Arabic: the whole interface is laid out right-to-left.
      builder: (context, child) => Directionality(
        textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: RemoteLongPress.guard,
          child: FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(requestFocusCallback: _smoothFocus),
            child: child!,
          ),
        ),
      ),
      home: const StartGate(),
    );
  }
}

DateTime _lastFocusMove = DateTime(2000);

void _smoothFocus(
  FocusNode node, {
  ScrollPositionAlignmentPolicy? alignmentPolicy,
  double? alignment,
  Duration? duration,
  Curve? curve,
}) {
  node.requestFocus();
  final ctx = node.context;
  if (ctx == null) return;
  // A single press glides; holding the button (fast repeats) jumps straight
  // there, so the animations don't pile up and lag behind.
  final now = DateTime.now();
  final holding = now.difference(_lastFocusMove) < const Duration(milliseconds: 180);
  _lastFocusMove = now;
  Scrollable.ensureVisible(
    ctx,
    alignment: 0.5,
    duration: holding ? Duration.zero : const Duration(milliseconds: 140),
    curve: Curves.easeOutCubic,
  );
}

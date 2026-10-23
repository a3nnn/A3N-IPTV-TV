import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'config.dart';
import 'data/storage.dart';
import 'screens/start_gate.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Storage.init();

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
    return MaterialApp(
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
      builder: (context, child) => FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(requestFocusCallback: _smoothFocus),
        child: child!,
      ),
      home: const StartGate(),
    );
  }
}

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
  Scrollable.ensureVisible(
    ctx,
    alignment: 0.5,
    duration: const Duration(milliseconds: 140),
    curve: Curves.easeOutCubic,
  );
}

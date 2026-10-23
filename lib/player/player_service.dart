import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../config.dart';
import '../data/storage.dart';

/// One shared player for the whole app, so switching channels is instant
/// and only one connection to the server is used at a time.
class PlayerService {
  PlayerService._() {
    player.setVolume(Storage.volume);
  }
  static final PlayerService instance = PlayerService._();

  final Player player = Player(
    configuration: PlayerConfiguration(
      title: AppConfig.appName,
      bufferSize: 64 * 1024 * 1024,
    ),
  );

  late final VideoController controller = VideoController(player);

  /// True while live TV is shown full window (hides the top bar and menu).
  final ValueNotifier<bool> fullscreen = ValueNotifier<bool>(false);

  String? _currentUrl;
  double _volumeBeforeMute = 100;

  Future<void> play(String url) async {
    if (_currentUrl == url) return;
    _currentUrl = url;
    await player.open(Media(url, httpHeaders: const {'User-Agent': AppConfig.userAgent}));
  }

  Future<void> stop() async {
    _currentUrl = null;
    await player.stop();
  }

  Future<void> setVolume(double v) => player.setVolume(v.clamp(0, 100));

  Future<void> toggleMute() async {
    final v = player.state.volume;
    if (v > 0) {
      _volumeBeforeMute = v;
      await player.setVolume(0);
      Storage.setVolume(0);
    } else {
      final restore = _volumeBeforeMute > 0 ? _volumeBeforeMute : 100.0;
      await player.setVolume(restore);
      Storage.setVolume(restore);
    }
  }

  Future<void> changeVolume(double delta) async {
    final v = (player.state.volume + delta).clamp(0.0, 100.0);
    await player.setVolume(v);
    Storage.setVolume(v);
  }
}

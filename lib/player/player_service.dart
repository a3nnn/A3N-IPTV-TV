import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../config.dart';
import '../data/storage.dart';

/// One shared player for the whole app, so switching channels is instant
/// and only one connection to the server is used at a time.
///
/// Tuned for TV boxes / TVs with little memory and a weak CPU:
///  * video is decoded AND drawn by the TV's hardware video chip
///    ("Fast" mode), so the CPU stays free for scrolling the lists;
///  * small network buffers, so memory never runs out.
class PlayerService {
  PlayerService._() {
    _tune();
  }
  static final PlayerService instance = PlayerService._();

  final Player player = Player(
    configuration: PlayerConfiguration(
      title: AppConfig.appName,
      // Demuxer cache. 16 MB is ~15 s of a 1080p live stream.
      bufferSize: 16 * 1024 * 1024,
    ),
  );

  /// "Fast"  = mediacodec (direct to the screen, lightest).
  /// "Compatible" = mediacodec-copy + GPU, for the rare TV where Fast shows a black picture.
  late final VideoController controller = VideoController(
    player,
    configuration: Storage.compatibleDecoder
        ? VideoControllerConfiguration(
            vo: 'gpu',
            hwdec: 'mediacodec-copy',
            enableHardwareAcceleration: true,
            width: 1280,
            height: 720,
          )
        : VideoControllerConfiguration(
            vo: 'mediacodec_embed',
            hwdec: 'mediacodec',
            enableHardwareAcceleration: true,
          ),
  );

  /// True while live TV is shown full screen (hides the menu).
  final ValueNotifier<bool> fullscreen = ValueNotifier<bool>(false);

  /// Bumped to ask the live screen to leave full screen (Android BACK fallback).
  final ValueNotifier<int> exitFullscreen = ValueNotifier<int>(0);

  String? _currentUrl;

  Future<void> _tune() async {
    // Extra mpv limits (ignored safely if a property is unknown).
    const props = <String, String>{
      'demuxer-max-back-bytes': '2097152', // no big rewind buffer for live TV
      'demuxer-readahead-secs': '10',
      'cache-pause-initial': 'no',
      'vd-lavc-threads': '2', // only used if software decoding kicks in
      'framedrop': 'vo',
      'video-sync': 'audio',
      'network-timeout': '20',
    };
    for (final e in props.entries) {
      try {
        await (player.platform as dynamic).setProperty(e.key, e.value);
      } catch (_) {}
    }
  }

  Future<void> play(String url) async {
    if (_currentUrl == url) return;
    _currentUrl = url;
    await player.open(Media(url, httpHeaders: const {'User-Agent': AppConfig.userAgent}));
  }

  Future<void> stop() async {
    _currentUrl = null;
    await player.stop();
  }
}

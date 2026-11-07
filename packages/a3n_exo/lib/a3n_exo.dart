import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// One audio / subtitle track of the stream on screen.
class ExoTrack {
  final String id;
  final String label;
  final String language;
  final bool selected;
  final bool supported;
  const ExoTrack(this.id, this.label, this.language, this.selected, this.supported);

  factory ExoTrack.fromMap(Map m) => ExoTrack('${m['id']}', '${m['label'] ?? ''}', '${m['language'] ?? ''}',
      m['selected'] == true, m['supported'] != false);
}

/// The A3N Android TV player (Media3 ExoPlayer on a native video surface).
class A3nExo {
  static const MethodChannel _m = MethodChannel('a3n_exo');
  static const EventChannel _e = EventChannel('a3n_exo/events');
  static Stream<Map<dynamic, dynamic>>? _events;

  /// {event: 'state' | 'tracks' | 'error', ...}
  static Stream<Map<dynamic, dynamic>> get events =>
      _events ??= _e.receiveBroadcastStream().map((x) => x as Map<dynamic, dynamic>).asBroadcastStream();

  static Future<void> open(String url, {required String userAgent, Duration start = Duration.zero}) =>
      _m.invokeMethod('open', {'url': url, 'userAgent': userAgent, 'startMs': start.inMilliseconds});
  static Future<void> stop() => _m.invokeMethod('stop');

  /// The screen is kept on now (a video plays).
  static Future<bool> awake() async => await _m.invokeMethod<bool>('awake') ?? false;
  static Future<void> play() => _m.invokeMethod('play');
  static Future<void> pause() => _m.invokeMethod('pause');
  static Future<void> seek(Duration to) => _m.invokeMethod('seek', {'ms': to.inMilliseconds});

  /// Preferred languages (ISO codes); [textOff] = no subtitles.
  static Future<void> setLanguages({List<String> audio = const [], List<String> text = const [], bool textOff = false}) =>
      _m.invokeMethod('setLanguages', {'audio': audio, 'text': text, 'textOff': textOff});

  static Future<(List<ExoTrack>, List<ExoTrack>)> tracks() async {
    final r = await _m.invokeMethod<Map<dynamic, dynamic>>('tracks');
    List<ExoTrack> list(String k) => [for (final e in (r?[k] as List? ?? const [])) ExoTrack.fromMap(e as Map)];
    return (list('audio'), list('text'));
  }

  static Future<void> selectAudio(String id) => _m.invokeMethod('selectAudio', {'id': id});

  /// [id] null = subtitles off.
  static Future<void> selectText(String? id) => _m.invokeMethod('selectText', {'id': id});

  static Future<void> subtitleStyle({required int color, required double scale, required bool background, required double opacity}) =>
      _m.invokeMethod('subtitleStyle', {'color': color, 'scale': scale, 'background': background, 'opacity': opacity});
}

/// The picture. Never takes the remote's focus.
class A3nExoView extends StatelessWidget {
  const A3nExoView({super.key});

  static const String _type = 'a3n_exo/view';

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      child: PlatformViewLink(
        viewType: _type,
        surfaceFactory: (context, controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        ),
        onCreatePlatformView: (params) {
          // A real Android view (hybrid composition): the video surface goes
          // straight from the TV's video chip to the screen.
          final c = PlatformViewsService.initExpensiveAndroidView(
            id: params.id,
            viewType: _type,
            layoutDirection: TextDirection.ltr,
            creationParamsCodec: const StandardMessageCodec(),
          );
          c.addOnPlatformViewCreatedListener(params.onPlatformViewCreated);
          c.create();
          return c;
        },
      ),
    );
  }
}

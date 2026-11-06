// Plays real streams through the app's player on an Android emulator
// (GitHub: player_test.yml): ExoPlayer on the native surface, the events,
// audio / subtitle tracks, seeking and stopping.
import 'dart:async';

import 'package:a3n_iptv_tv/data/storage.dart';
import 'package:a3n_iptv_tv/player/player_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

// Apple's public test streams (HLS): H.264 with subtitles in several languages.
const _hls = 'https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8';
// A plain MP4 file (like a movie).
const _mp4 = 'https://storage.googleapis.com/exoplayer-test-media-0/BigBuckBunny_320x180.mp4';

Future<bool> _until(WidgetTester t, bool Function() ok, {int seconds = 60}) async {
  for (var i = 0; i < seconds * 4; i++) {
    if (ok()) return true;
    await t.pump(const Duration(milliseconds: 250));
  }
  return ok();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ExoPlayer: plays, reports, tracks, seek, stop', (t) async {
    MediaKit.ensureInitialized();
    await Storage.init();
    await Storage.setPlayerEngine('exo');
    await Storage.setSubtitleLang('ar');
    final p = PlayerService.instance;
    expect(p.isExo, isTrue);

    await t.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox.expand(child: p.view()))));

    // ---- HLS stream
    await p.play(_hls);
    final playing = await _until(t, () => p.playing && p.videoSize.$2 > 0);
    // ignore: avoid_print
    print('HLS: playing=${p.playing} size=${p.videoSize} buffering=${p.buffering}');
    expect(playing, isTrue, reason: 'the HLS stream should play with a picture');
    final fps = await p.frameRate();
    // ignore: avoid_print
    print('HLS fps=$fps extra="${p.videoExtra}"');

    final (audio, subs) = await p.tracks();
    // ignore: avoid_print
    print('audio=${audio.map((a) => '${a.language}/${a.title}/${a.selected}').toList()} '
        'subs=${subs.map((s) => '${s.language}/${s.title}/${s.selected}').toList()}');
    expect(audio, isNotEmpty);
    expect(subs, isNotEmpty, reason: 'this stream has subtitles');
    // Settings say Arabic: the file's default English subtitles are turned off.
    await t.pump(const Duration(seconds: 2));
    final (_, subsAr) = await p.tracks();
    expect(subsAr.any((s) => s.selected), isFalse, reason: 'no Arabic subtitles in this stream: off');

    await p.selectSubtitle(subs.first.id);
    await t.pump(const Duration(seconds: 2));
    final (_, subs2) = await p.tracks();
    expect(subs2.firstWhere((s) => s.id == subs.first.id).selected, isTrue, reason: 'subtitle selected');
    await p.selectSubtitle(null);
    await t.pump(const Duration(seconds: 2));
    final (_, subs3) = await p.tracks();
    expect(subs3.any((s) => s.selected), isFalse, reason: 'subtitles off');

    // ---- MP4 file: duration, seek, pause / resume
    await p.play(_mp4);
    final ok = await _until(t, () => p.playing && p.duration > Duration.zero);
    // ignore: avoid_print
    print('MP4: playing=${p.playing} duration=${p.duration} size=${p.videoSize}');
    expect(ok, isTrue, reason: 'the MP4 should play');
    await p.seek(const Duration(seconds: 60));
    final seeked = await _until(t, () => p.position >= const Duration(seconds: 59), seconds: 30);
    // ignore: avoid_print
    print('after seek: position=${p.position}');
    expect(seeked, isTrue);
    await p.pause();
    expect(await _until(t, () => !p.playing, seconds: 10), isTrue);
    await p.resume();
    expect(await _until(t, () => p.playing, seconds: 15), isTrue);

    await p.stop();
    await t.pump(const Duration(seconds: 1));
    expect(p.playing, isFalse);
  });
}

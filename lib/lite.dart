import 'data/storage.dart';

/// "Light mode" from Settings, for weak devices such as a Fire Stick:
/// no preview while browsing, no animations, smaller pictures and a
/// lighter video player. Read at start, so the app is reopened after
/// changing it.
class Lite {
  static bool get on => Storage.liteMode;

  /// Animation length: none in light mode.
  static Duration anim(int ms) => on ? Duration.zero : Duration(milliseconds: ms);

  /// Picture decode width: about 60 % in light mode (less memory).
  static int? img(int? width) => (width == null || !on) ? width : (width * 0.6).round();
}

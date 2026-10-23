# A3N IPTV Player — Android TV

IPTV player for **Android TV (Android 12+)**, built with Flutter and [media_kit](https://github.com/media-kit/media-kit) (libmpv).

> **A3N IPTV Player is a media player only.** It does not provide, host or distribute any channels, streams or playlists. You need your own Xtream Codes subscription.

## Download (Downloader app)

**https://github.com/a3nnn/A3N-IPTV-TV/releases/latest/download/A3N_IPTV_Player.apk**

## Features

- Xtream Codes login
- Live TV with categories, search, favorites and pinned categories
- Program guide (now / next), full screen with ▲ ▼ channel switching
- Movies and series with OK = play/pause, ◀ ▶ = seek
- Built for the TV remote (D-pad)

## Build

Releases are built automatically by GitHub Actions (`.github/workflows/release.yml`) when a version tag (`v*`) is pushed. The Android project is generated in CI and patched for Android TV by `ci/patch_android.py`.

## Privacy

The app connects to the IPTV server in `lib/config.dart`. When usage monitoring is enabled, each time the app starts and every 10 minutes while it runs it sends to the maintainer's database: the signed-in username, the TV model, a random device ID, the Android version, the app version, the IP address and its approximate location (country, city, internet provider, via ipwho.is). This is used to see who is using the app and to disable it on specific devices.

## License

[MIT](LICENSE)

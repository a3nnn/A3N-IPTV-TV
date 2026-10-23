import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'storage.dart';

class LicenseStatus {
  final bool blocked;
  final String? message;
  const LicenseStatus(this.blocked, this.message);

  static const allowed = LicenseStatus(false, null);
}

/// Reports this device to your Supabase project and asks whether the app is
/// blocked here. Your Xtream subscription is never touched.
///
/// If Supabase can't be reached, the last known answer is used, so a blocked
/// device stays blocked even offline, and a normal device keeps working.
class LicenseService {
  static bool get enabled => AppConfig.supabaseUrl.isNotEmpty && AppConfig.supabaseKey.isNotEmpty;

  static LicenseStatus get cached =>
      Storage.licenseBlocked ? LicenseStatus(true, Storage.licenseMessage) : LicenseStatus.allowed;

  static Map<String, String?>? _geo;

  /// Approximate location of the current internet connection (country, city,
  /// provider). Looked up once per app start.
  static Future<Map<String, String?>> _location() async {
    if (_geo != null) return _geo!;
    try {
      final res = await http
          .get(Uri.parse('https://ipwho.is/?fields=success,country,city,connection'))
          .timeout(const Duration(seconds: 4));
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is Map && data['success'] == true) {
        final conn = data['connection'] is Map ? data['connection'] as Map : const {};
        _geo = {
          'country': data['country']?.toString(),
          'city': data['city']?.toString(),
          'isp': (conn['isp'] ?? conn['org'])?.toString(),
        };
        return _geo!;
      }
    } catch (_) {}
    return const {'country': null, 'city': null, 'isp': null};
  }

  static Future<LicenseStatus> check({required String username, bool opened = false}) async {
    if (!enabled) return LicenseStatus.allowed;
    try {
      final geo = await _location();
      final base = AppConfig.supabaseUrl.endsWith('/')
          ? AppConfig.supabaseUrl.substring(0, AppConfig.supabaseUrl.length - 1)
          : AppConfig.supabaseUrl;
      final res = await http
          .post(
            Uri.parse('$base/rest/v1/rpc/checkin'),
            headers: {
              'apikey': AppConfig.supabaseKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'p_device_id': Storage.deviceId,
              'p_username': username,
              'p_device_name': await _deviceName(),
              'p_os': 'Android TV ${await _androidVersion()}',
              'p_app_version': AppConfig.version,
              'p_opened': opened,
              'p_country': geo['country'],
              'p_city': geo['city'],
              'p_isp': geo['isp'],
            }),
          )
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return cached;

      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! Map) return cached;
      final blocked = data['blocked'] == true;
      final message = data['message']?.toString();
      await Storage.setLicense(blocked, message);
      return LicenseStatus(blocked, message);
    } catch (_) {
      return cached;
    }
  }

  static String? _name;
  static String? _release;

  static Future<String> _androidVersion() async {
    if (_release != null) return _release!;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      _release = 'Android ${info.version.release} (SDK ${info.version.sdkInt})';
    } catch (_) {
      _release = '';
    }
    return _release!;
  }

  /// TV model, e.g. "Xiaomi Mi Box S" or "Google Chromecast HD".
  static Future<String> _deviceName() async {
    if (_name != null) return _name!;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final maker = info.manufacturer.trim();
      final model = info.model.trim();
      _name = model.toLowerCase().startsWith(maker.toLowerCase()) ? model : '$maker $model';
    } catch (_) {
      _name = 'Android TV';
    }
    return _name!;
  }
}

import 'package:flutter/material.dart';

/// ===============================================================
///  إعدادات التطبيق — كل شي تبي تغيّره موجود هنا
/// ===============================================================
class AppConfig {
  // ---------- الهوست ----------
  // اكتب رابط سيرفر الـ Xtream مع البورت، بدون / في الآخر
  // مثال: http://example.com:8080
  static const String host = 'http://292910.xyz:8080';

  // ---------- الهوية ----------
  static const String appName = 'A3N IPTV Player';
  static const String signature = 'Made by A3N';
  static const String version = '1.0.5';

  // ---------- مراقبة الأجهزة والإيقاف (Supabase) ----------
  // من Supabase: Project Settings > API Keys
  // اتركهم فاضيين إذا تبي توقف الميزة
  static const String supabaseUrl = 'https://maprkkxrejioanbmmkfx.supabase.co';
  static const String supabaseKey = 'sb_publishable_7qnYao15KzzWbN928bPIIQ_ChFNEAL-'; // Publishable key (sb_publishable_...)

  // ---------- التشغيل ----------
  // صيغة البث المباشر: 'ts' (الأفضل غالباً) أو 'm3u8'
  static const String liveFormat = 'ts';
  // إذا السيرفر رفض الاتصال جرّب تغيّره إلى: 'VLC/3.0.20 LibVLC/3.0.20'
  static const String userAgent = 'A3N IPTV Player/1.0';

  // ---------- الألوان ----------
  static const Color background = Color(0xFF0B0E14);
  static const Color surface = Color(0xFF131821);
  static const Color surfaceHigh = Color(0xFF1B2230);
  static const Color divider = Color(0xFF222A37);
  static const Color primary = Color(0xFF00C2A8); // اللون الأساسي
  static const Color accent = Color(0xFFFFB020); // لون المفضلة والتنبيهات
  static const Color textPrimary = Color(0xFFE8ECF2);
  static const Color textSecondary = Color(0xFF8A94A6);
  static const Color danger = Color(0xFFFF5A5F);
}

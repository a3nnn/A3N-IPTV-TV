import 'dart:convert';

import 'package:flutter/material.dart';

String asString(dynamic v) => v == null ? '' : v.toString();

int asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    return int.tryParse(v.trim()) ?? double.tryParse(v.trim())?.toInt() ?? fallback;
  }
  return fallback;
}

double asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim()) ?? 0;
  return 0;
}

/// Xtream EPG titles are usually base64 encoded.
String decodeB64(String s) {
  if (s.isEmpty) return s;
  try {
    return utf8.decode(base64.decode(base64.normalize(s.trim())));
  } catch (_) {
    return s;
  }
}

Color fade(Color c, double opacity) => c.withAlpha((opacity * 255).round());

String two(int n) => n.toString().padLeft(2, '0');

String fmtTime(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

String fmtDate(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

/// For search: lower case, and the Arabic letter variants treated as one
/// (أ إ آ → ا, ى → ي, ة → ه), without tashkeel.
String searchNorm(String s) {
  var t = s.toLowerCase();
  t = t.replaceAll(RegExp('[ً-ْـ]'), '');
  t = t.replaceAll(RegExp('[أإآٱ]'), 'ا').replaceAll('ى', 'ي').replaceAll('ة', 'ه');
  return t;
}

import 'dart:convert';
import 'package:flutter/services.dart';

class RingLogService {
  static const MethodChannel _channel = MethodChannel('no_mercy_alarm/alarm');

  static Future<int> getLastRungIdx() async {
    final v = await _channel.invokeMethod<dynamic>('ringLog_getLastRungIdx');
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static Future<Map<String, dynamic>?> getLastEvent() async {
    final raw = await _channel.invokeMethod<dynamic>('ringLog_getLastEvent');
    if (raw == null) return null;
    if (raw is! String) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    await _channel.invokeMethod('ringLog_clear');
  }
}
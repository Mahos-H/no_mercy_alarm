import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alarm_model.dart';

class AlarmService {
  static late SharedPreferences _prefs;

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static const _ringingKey = 'alarm_ringing';
  static const _activeAlarmIdKey = 'active_alarm_id';

  static const MethodChannel _channel = MethodChannel('no_mercy_alarm/alarm');

  static final _alarmsController =
      StreamController<List<AlarmModel>>.broadcast();
  static Stream<List<AlarmModel>> get alarmsStream => _alarmsController.stream;

  static final RegExp _alarmKeyPattern = RegExp(r'^alarm_(\d+)$');

  static Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    await _notifications.initialize(
      settings: const InitializationSettings(android: androidInit),
    );

    const channel = AndroidNotificationChannel(
      'alarm_channel',
      'Alarms',
      description: 'Critical alarm notifications',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
    );

    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(channel);

    final alarms = await getAllAlarms();
    _alarmsController.add(alarms);
  }

  static Future<void> scheduleAlarm(AlarmModel alarm) async {
    await _prefs.setString('alarm_${alarm.id}', jsonEncode(alarm.toJson()));

    await _channel.invokeMethod('scheduleExactAlarm', {
      'alarmId': alarm.id,
      'triggerAtMillis': alarm.time.millisecondsSinceEpoch,
    });

    final alarms = await getAllAlarms();
    _alarmsController.add(alarms);
  }

  static Future<List<AlarmModel>> getAllAlarms() async {
    final alarmKeys = _prefs
        .getKeys()
        .where((k) => _alarmKeyPattern.hasMatch(k))
        .toList(growable: false);

    final alarms = <AlarmModel>[];

    for (final key in alarmKeys) {
      final raw = _prefs.get(key);

      if (raw == null) continue;

      if (raw is! String) {
        await _prefs.remove(key);
        continue;
      }

      try {
        final alarm = AlarmModel.fromJson(jsonDecode(raw));
        alarms.add(alarm);
      } catch (_) {
        await _prefs.remove(key);
      }
    }

    alarms.sort((a, b) => a.time.compareTo(b.time));
    return alarms;
  }

  static Future<AlarmModel?> getAlarmById(int id) async {
    final jsonStr = _prefs.getString('alarm_$id');
    if (jsonStr == null) return null;

    try {
      return AlarmModel.fromJson(jsonDecode(jsonStr));
    } catch (_) {
      return null;
    }
  }

  /// Option C: keep alarm in prefs while ringing; we do not use this.
  /// (You can delete this method if nothing else references it.)
  static Future<void> deleteAlarmFromMenuOnly(int alarmId) async {
    await _prefs.remove('alarm_${alarmId}_first_wrong_at_ms');
    await _prefs.remove('alarm_$alarmId');

    final alarms = await getAllAlarms();
    _alarmsController.add(alarms);
  }

  static Future<void> stopAlarmAndCleanup({required int alarmId}) async {
    await _channel.invokeMethod('stopAndAdvanceQueue', {'alarmId': alarmId});

    await _notifications.cancel(id: alarmId);

    await _prefs.remove('alarm_${alarmId}_first_wrong_at_ms');
    await _prefs.remove('alarm_$alarmId');

    final alarms = await getAllAlarms();
    _alarmsController.add(alarms);
  }

  static Future<void> cancelAlarm(int id) async {
    await _prefs.remove('alarm_${id}_first_wrong_at_ms');
    await _prefs.remove('alarm_$id');
    await _channel.invokeMethod('cancelExactAlarm', {'alarmId': id});

    final alarms = await getAllAlarms();
    _alarmsController.add(alarms);
  }

  /// Returns the active alarm id if known.
  /// - Prefer Dart prefs
  /// - Fallback to native queue (so HomeScreen can disable delete reliably)
  static Future<int?> getActiveAlarmId() async {
    final id = _prefs.getInt(_activeAlarmIdKey);
    if (id != null) return id;

    try {
      final nativeActive =
          await _channel.invokeMethod<dynamic>('ringQueue_getActiveAlarmId');
      final nativeId = (nativeActive is int)
          ? nativeActive
          : int.tryParse(nativeActive?.toString() ?? '');
      return nativeId;
    } catch (_) {
      return null;
    }
  }

  static Future<AlarmModel?> getActiveAlarm() async {
    final id = await getActiveAlarmId();
    if (id == null) return null;

    final jsonStr = _prefs.getString('alarm_$id');
    if (jsonStr == null) return null;

    try {
      return AlarmModel.fromJson(jsonDecode(jsonStr));
    } catch (_) {
      return null;
    }
  }

  static Future<void> stopAlarm() async {
    final id = _prefs.getInt(_activeAlarmIdKey);

    if (id != null) {
      await _channel.invokeMethod('stopAndAdvanceQueue', {'alarmId': id});
    } else {
      final nativeId = await getActiveAlarmId();
      if (nativeId != null) {
        await _channel.invokeMethod('stopAndAdvanceQueue', {'alarmId': nativeId});
      } else {
        // As a last resort, try stopping audio without queue advancement.
        try {
          await _channel.invokeMethod('stopRingingService');
        } catch (_) {}
      }
    }

    if (id != null) {
      await _notifications.cancel(id: id);
    }

    await _prefs.setBool(_ringingKey, false);
    await _prefs.remove(_activeAlarmIdKey);

    if (id != null) {
      await _prefs.remove('alarm_${id}_first_wrong_at_ms');
      await _prefs.remove('alarm_$id');
    }

    final alarms = await getAllAlarms();
    _alarmsController.add(alarms);
  }

  static Future<void> showAlarmNotification(int alarmId) async {
    final androidDetails = AndroidNotificationDetails(
      'alarm_channel',
      'Alarms',
      channelDescription: 'Critical alarm notifications',
      importance: Importance.max,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
      enableLights: true,
      ticker: 'ALARM RINGING NOW!',
      styleInformation: const BigTextStyleInformation(
        '🚨 YOUR ALARM IS RINGING! Open the app and enter your password to stop it.',
        contentTitle: '⏰ ALARM RINGING!',
        summaryText: 'TAP TO STOP',
      ),
    );

    await _notifications.show(
      id: alarmId,
      title: '⏰ ALARM RINGING!',
      body: 'Open to stop the alarm',
      notificationDetails: NotificationDetails(android: androidDetails),
    );
  }

  static Future<void> clearAllData() async {
    // 1) Cancel scheduled alarms first (so they don't keep firing after prefs wipe)
    final alarms = await getAllAlarms();
    final activeId = await getActiveAlarmId();

    for (final a in alarms) {
      try {
        await _channel.invokeMethod('cancelExactAlarm', {'alarmId': a.id});
      } catch (_) {}
      try {
        await _notifications.cancel(id: a.id);
      } catch (_) {}
    }

    // 2) Stop ringing audio (native) safely:
    // Never pass null alarmId into stopAndAdvanceQueue.
    if (activeId != null) {
      try {
        await _channel.invokeMethod('stopAndAdvanceQueue', {'alarmId': activeId});
      } catch (_) {}
    } else {
      // Best-effort fallback
      try {
        await _channel.invokeMethod('stopRingingService');
      } catch (_) {}
    }

    // 3) Clear native queue + ring log
    try {
      await _channel.invokeMethod('ringQueue_clear');
    } catch (_) {}
    try {
      await _channel.invokeMethod('ringLog_clear');
    } catch (_) {}

    // 4) Clear Dart prefs
    await _prefs.clear();

    // 5) Update stream
    _alarmsController.add(const <AlarmModel>[]);
  }

  static void dispose() {
    // App-lifetime singleton: intentionally no-op.
    // If you ever need to dispose in tests, close _alarmsController there.
  }
}
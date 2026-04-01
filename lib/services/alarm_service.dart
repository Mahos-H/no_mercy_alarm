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

  // Only accept keys like "alarm_123" (numeric id), not "alarm_ringing", etc.
  static final RegExp _alarmKeyPattern = RegExp(r'^alarm_(\d+)$');

  // ================= INITIALIZATION =================

  static Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    await _notifications.initialize(
      settings: const InitializationSettings(android: androidInit),
    );

    // Create notification channel (Android)
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

    // Seed stream
    final alarms = await getAllAlarms();
    _alarmsController.add(alarms);
  }

  // ================= ALARM STORAGE + SCHEDULING =================

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
    // Filter keys strictly to alarm_<number>
    final alarmKeys = _prefs
        .getKeys()
        .where((k) => _alarmKeyPattern.hasMatch(k))
        .toList(growable: false);

    final alarms = <AlarmModel>[];

    for (final key in alarmKeys) {
      // SAFETY: shared_preferences throws if underlying type is not String.
      // So we read the raw map to check the type first.
      final raw = _prefs.get(key);

      if (raw == null) continue;

      if (raw is! String) {
        // Unexpected type under alarm_* key — remove it to prevent future crashes.
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

    // Sort by scheduled time (not creation time)
    alarms.sort((a, b) => a.time.compareTo(b.time));
    return alarms;
  }

  static Future<AlarmModel?> getAlarmById(int id) async {
    // Reads the stored JSON for this alarm id
    final jsonStr = _prefs.getString('alarm_$id');
    if (jsonStr == null) return null;

    try {
      return AlarmModel.fromJson(jsonDecode(jsonStr));
    } catch (_) {
      return null;
    }
  }

  /// Deletes an alarm from the in-app list (SharedPreferences + stream),
  /// but does NOT attempt to stop ringing audio and does NOT cancel alarms
  /// at the Android AlarmManager level.
  ///
  /// Use this when an alarm is already ringing, and you want to prevent the
  /// user from "deleting to stop it".
  static Future<void> deleteAlarmFromMenuOnly(int alarmId) async {
    await _prefs.remove('alarm_${alarmId}_first_wrong_at_ms');
    await _prefs.remove('alarm_$alarmId');

    final alarms = await getAllAlarms();
    _alarmsController.add(alarms);
  }

  static Future<void> stopAlarmAndCleanup({required int alarmId}) async {
    // stop native ringing service (audio)
    await _channel.invokeMethod('stopAndAdvanceQueue', {'alarmId': alarmId});

    // clear notification if any
    await _notifications.cancel(id: alarmId);

    // clear any wrong-at timestamp + remove alarm (one-shot)
    await _prefs.remove('alarm_${alarmId}_first_wrong_at_ms');
    await _prefs.remove('alarm_$alarmId');

    final alarms = await getAllAlarms();
    _alarmsController.add(alarms);
  }

  static Future<void> cancelAlarm(int id) async {
    await _prefs.remove('alarm_$id');
    await _channel.invokeMethod('cancelExactAlarm', {'alarmId': id});

    final alarms = await getAllAlarms();
    _alarmsController.add(alarms);
  }

  // ================= RINGING STATE =================

  static Future<AlarmModel?> getActiveAlarm() async {
    final id = _prefs.getInt(_activeAlarmIdKey);
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

    // stop native ringing service (audio) + advance queue
    if (id != null) {
      await _channel.invokeMethod('stopAndAdvanceQueue', {'alarmId': id});
    } else {
      // fallback: ask native for the active alarm id
      final nativeActive =
          await _channel.invokeMethod<dynamic>('ringQueue_getActiveAlarmId');
      final nativeId = (nativeActive is int)
          ? nativeActive
          : int.tryParse(nativeActive?.toString() ?? '');
      if (nativeId != null) {
        await _channel.invokeMethod('stopAndAdvanceQueue', {'alarmId': nativeId});
      }
    }

    // clear notification if any
    if (id != null) {
      await _notifications.cancel(id: id);
    }

    await _prefs.setBool(_ringingKey, false);
    await _prefs.remove(_activeAlarmIdKey);

    if (id != null) {
      await _prefs.remove('alarm_${id}_first_wrong_at_ms');
      await _prefs.remove('alarm_$id'); // one-shot behavior
    }

    final alarms = await getAllAlarms();
    _alarmsController.add(alarms);
  }

  // ================= OPTIONAL: HEADS-UP NOTIFICATION =================
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
    final id = _prefs.getInt(_activeAlarmIdKey);
    for (final a in alarms) {
      try {
        await _channel.invokeMethod('cancelExactAlarm', {'alarmId': a.id});
      } catch (_) {
        // ignore best-effort
      }
      try {
        await _notifications.cancel(id: a.id);
      } catch (_) {}
    }

    // 2) Stop ringing audio (native)
    try {
      await _channel.invokeMethod('stopAndAdvanceQueue', {'alarmId': id});
    } catch (_) {}

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

  // Dispose note: see section 3 below (we will not close controller in app lifetime)
  static void dispose() {
    //
  }
}
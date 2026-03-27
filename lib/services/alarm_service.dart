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

  static final _alarmsController = StreamController<List<AlarmModel>>.broadcast();
  static Stream<List<AlarmModel>> get alarmsStream => _alarmsController.stream;

  // ================= INITIALIZATION =================

  static Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    await _notifications.initialize(
      settings: const InitializationSettings(android: androidInit),
      // (optional) callbacks:
      // onDidReceiveNotificationResponse: (resp) {},
      // onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
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
    final keys = _prefs.getKeys().where((k) =>
        k.startsWith('alarm_') && k != _ringingKey && k != _activeAlarmIdKey);

    final alarms = <AlarmModel>[];
    for (final key in keys) {
      final str = _prefs.getString(key);
      if (str == null) continue;

      try {
        final alarm = AlarmModel.fromJson(jsonDecode(str));
        alarms.add(alarm);
      } catch (_) {
        await _prefs.remove(key);
      }
    }

    alarms.sort((a, b) => a.time.compareTo(b.time));
    return alarms;
  }

  static Future<void> cancelAlarm(int id) async {
    await _prefs.remove('alarm_$id');
    await _channel.invokeMethod('cancelExactAlarm', {'alarmId': id});

    final alarms = await getAllAlarms();
    _alarmsController.add(alarms);
  }

  // ================= RINGING STATE =================

  static Future<bool> isAlarmRinging() async {
    return _prefs.getBool(_ringingKey) ?? false;
  }

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

    // stop native ringing service (audio)
    await _channel.invokeMethod('stopRingingService');

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

  static void dispose() {
    _alarmsController.close();
  }
}
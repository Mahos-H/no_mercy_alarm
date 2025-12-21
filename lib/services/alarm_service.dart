import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alarm_model.dart';

class AlarmService {
  static late SharedPreferences _prefs;
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static const _ringingKey = 'alarm_ringing';
  static const _activeAlarmIdKey = 'active_alarm_id';

  static final _alarmsController = StreamController<List<AlarmModel>>.broadcast();
  static Stream<List<AlarmModel>> get alarmsStream => _alarmsController.stream;

  // Timer for checking alarms
  static Timer? _alarmCheckTimer;

  // ================= INITIALIZATION =================

  static Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();

    print('🚀 Initializing AlarmService...');

    // Initialize notifications
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifications.initialize(
      const InitializationSettings(android: androidInit),
    );

    // Create notification channel
    const channel = AndroidNotificationChannel(
      'alarm_channel',
      'Alarms',
      description: 'Critical alarm notifications',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Start checking for alarms every second
    _startAlarmChecker();

    print('✅ AlarmService initialized');
  }

  static void _startAlarmChecker() {
    _alarmCheckTimer?.cancel();
    _alarmCheckTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final alarms = await getAllAlarms();
      final now = DateTime.now();

      for (final alarm in alarms) {
        // Check if alarm time has been reached (within 2 seconds tolerance)
        final difference = alarm.time.difference(now).inSeconds;
        if (difference <= 1 && difference >= -1) {
          print('⏰ Alarm ${alarm.id} should ring now! Time: ${alarm.time}, Now: $now');
          await _triggerAlarm(alarm.id);
        }
      }
    });
    print('✅ Alarm checker started - checking every second');
  }

  // ================= TRIGGER ALARM =================

  static Future<void> _triggerAlarm(int alarmId) async {
    print('');
    print('═══════════════════════════════════════════════');
    print('🚨 TRIGGERING ALARM: $alarmId');
    print('   Time: ${DateTime.now()}');
    print('═══════════════════════════════════════════════');

    // Check if already ringing
    final isRinging = _prefs.getBool(_ringingKey) ?? false;
    if (isRinging) {
      print('⚠️ Alarm already ringing, skipping');
      return;
    }

    // Set ringing state
    await _prefs.setBool(_ringingKey, true);
    await _prefs.setInt(_activeAlarmIdKey, alarmId);

    // Show notification with MAXIMUM settings
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
      color: Color(0xFFFF0000),
      ledColor: Color(0xFFFF0000),
      ledOnMs: 1000,
      ledOffMs: 500,
      ticker: 'ALARM RINGING NOW!',
      styleInformation: BigTextStyleInformation(
        '🚨 YOUR ALARM IS RINGING! Tap here immediately to open the app and enter your password to stop it.',
        htmlFormatBigText: true,
        contentTitle: '⏰⏰⏰ ALARM RINGING! ⏰⏰⏰',
        htmlFormatContentTitle: true,
        summaryText: 'TAP TO STOP',
        htmlFormatSummaryText: true,
      ),
    );

    await _notifications.show(
      alarmId,
      '⏰ ALARM RINGING!',
      'TAP HERE NOW to stop the alarm',
      NotificationDetails(android: androidDetails),
    );

    print('📱 Notification shown for alarm $alarmId');
    print('═══════════════════════════════════════════════');
    print('');
  }

  // ================= ALARM STORAGE =================

  static Future<void> scheduleAlarm(AlarmModel alarm) async {
    print('');
    print('📝 Scheduling alarm: ${alarm.id}');
    print('   Time: ${alarm.time}');
    print('   Now: ${DateTime.now()}');
    print('   Seconds until alarm: ${alarm.time.difference(DateTime.now()).inSeconds}');

    // Save to SharedPreferences
    await _prefs.setString(
      'alarm_${alarm.id}',
      jsonEncode(alarm.toJson()),
    );

    // Notify listeners
    final alarms = await getAllAlarms();
    _alarmsController.add(alarms);
    
    print('✅ Alarm saved successfully');
    print('   Alarm checker will trigger it automatically');
    print('');
  }

  static Future<List<AlarmModel>> getAllAlarms() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith('alarm_'));
    final alarms = <AlarmModel>[];
    final now = DateTime.now();

    for (final key in keys) {
      final str = _prefs.getString(key);
      if (str == null) continue;

      try {
        final alarm = AlarmModel.fromJson(jsonDecode(str));
        // Keep alarms that are in the future OR very recently past (within 5 seconds)
        if (alarm.time.isAfter(now.subtract(const Duration(seconds: 5)))) {
          alarms.add(alarm);
        } else {
          await _prefs.remove(key);
          print('🗑️ Removed old alarm: $key');
        }
      } catch (e) {
        print('⚠️ Error parsing alarm $key: $e');
      }
    }

    alarms.sort((a, b) => a.time.compareTo(b.time));
    return alarms;
  }

  static Future<void> cancelAlarm(int id) async {
    print('🗑️ Canceling alarm $id');
    await _prefs.remove('alarm_$id');

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

    final json = _prefs.getString('alarm_$id');
    if (json == null) return null;

    try {
      return AlarmModel.fromJson(jsonDecode(json));
    } catch (e) {
      return null;
    }
  }

  static Future<void> stopAlarm() async {
    print('🛑 Stopping alarm');
    
    final id = _prefs.getInt(_activeAlarmIdKey);
    if (id != null) {
      await _notifications.cancel(id);
      await _prefs.remove('alarm_$id');
    }

    await _prefs.setBool(_ringingKey, false);
    await _prefs.remove(_activeAlarmIdKey);

    final alarms = await getAllAlarms();
    _alarmsController.add(alarms);
  }

  static void dispose() {
    _alarmCheckTimer?.cancel();
    _alarmsController.close();
  }
}
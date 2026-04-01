import 'dart:async';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'services/alarm_service.dart';
import 'services/ring_log_service.dart';
import 'screens/home_screen.dart';
import 'screens/alarm_ringing_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AndroidAlarmManager.initialize();

  await AlarmService.initialize();
  await _requestPermissions();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const NoMercyAlarmApp());
}

Future<void> _requestPermissions() async {
  await Permission.notification.request();

  try {
    if (await Permission.scheduleExactAlarm.isDenied) {
      await Permission.scheduleExactAlarm.request();
    }
  } catch (_) {}
}

class NoMercyAlarmApp extends StatelessWidget {
  const NoMercyAlarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'No Snooze Alarm',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          elevation: 0,
          centerTitle: true,
          backgroundColor: Colors.blue.shade700,
          foregroundColor: Colors.white,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: Colors.blue.shade700,
          foregroundColor: Colors.white,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
      ),
      home: const AlarmCheckerScreen(),
    );
  }
}

class AlarmCheckerScreen extends StatefulWidget {
  const AlarmCheckerScreen({super.key});

  @override
  State<AlarmCheckerScreen> createState() => _AlarmCheckerScreenState();
}

class _AlarmCheckerScreenState extends State<AlarmCheckerScreen>
    with WidgetsBindingObserver {
  bool _navigated = false;

  Timer? _pollTimer;
  bool _checking = false;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  static const Duration _foregroundPollInterval = Duration(seconds: 2);

  static const Duration _burstInterval = Duration(milliseconds: 500);
  static const Duration _burstDuration = Duration(seconds: 10);
  Timer? _burstTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _checkAndRoute();
    _startPolling();
    _startBurst();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    _stopBurst();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;

    if (state == AppLifecycleState.resumed) {
      _startPolling();
      _startBurst();
      _checkAndRoute();
    } else {
      _stopPolling();
      _stopBurst();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_foregroundPollInterval, (_) {
      if (!mounted) return;
      if (_lifecycle != AppLifecycleState.resumed) return;
      _checkAndRoute();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _startBurst() {
    _stopBurst();

    _burstTimer = Timer.periodic(_burstInterval, (_) {
      if (!mounted) return;
      if (_lifecycle != AppLifecycleState.resumed) return;
      _checkAndRoute();
    });

    Timer(_burstDuration, () {
      _stopBurst();
    });
  }

  void _stopBurst() {
    _burstTimer?.cancel();
    _burstTimer = null;
  }

  Future<void> _checkAndRoute() async {
    if (_navigated) return;
    if (_checking) return;
    _checking = true;

    try {
      final lastEvent = await RingLogService.getLastEvent();
      if (!mounted) return;
      if (lastEvent == null) return;

      final state = (lastEvent['state'] ?? '').toString();
      if (state != 'FIRED' && state != 'SHOWN') {
        return;
      }

      final alarmIdRaw = lastEvent['alarmId'];
      final alarmId = alarmIdRaw is int
          ? alarmIdRaw
          : int.tryParse(alarmIdRaw?.toString() ?? '');
      if (alarmId == null) return;

      // Option C: do NOT delete from prefs/menu here.
      final alarm = await AlarmService.getAlarmById(alarmId);
      if (!mounted) return;
      if (alarm == null) return;

      _navigated = true;
      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (_) => AlarmRingingScreen(alarm: alarm),
            ),
          )
          .then((_) {
        _navigated = false;
      });
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}
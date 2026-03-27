import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'services/alarm_service.dart';
import 'screens/home_screen.dart';
import 'screens/alarm_ringing_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // AlarmManager must be initialized before you use it (even if scheduling is native)
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

  await Permission.storage.request();
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAndRoute();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndRoute();
    }
  }

  Future<void> _checkAndRoute() async {
    if (_navigated) return;

    final isRinging = await AlarmService.isAlarmRinging();
    if (!mounted) return;

    if (isRinging) {
      final alarm = await AlarmService.getActiveAlarm();
      if (!mounted) return;
      if (alarm != null) {
        _navigated = true;
        Navigator.of(context)
            .pushReplacement(
              MaterialPageRoute(
                builder: (_) => AlarmRingingScreen(alarm: alarm),
              ),
            )
            .then((_) => _navigated = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}
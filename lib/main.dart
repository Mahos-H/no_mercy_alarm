import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/alarm_service.dart';
import 'screens/home_screen.dart';
import 'screens/alarm_ringing_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize alarm service
  await AlarmService.initialize();

  // Request permissions
  await _requestPermissions();

  // Lock orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const NoMercyAlarmApp());
}

Future<void> _requestPermissions() async {
  // Request notification permission
  await Permission.notification.request();

  // Request exact alarm permission (Android 12+). Some platforms may not expose this via permission_handler;
  // handle gracefully if not available.
  try {
    if (await Permission.scheduleExactAlarm.isDenied) {
      await Permission.scheduleExactAlarm.request();
    }
  } catch (_) {
    // ignore if permission isn't available on the platform / package version
  }

  // Request storage permission for custom sounds
  await Permission.storage.request();
}

class NoMercyAlarmApp extends StatelessWidget {
  const NoMercyAlarmApp({Key? key}) : super(key: key);

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
  const AlarmCheckerScreen({Key? key}) : super(key: key);

  @override
  State<AlarmCheckerScreen> createState() => _AlarmCheckerScreenState();
}

class _AlarmCheckerScreenState extends State<AlarmCheckerScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAlarmStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAlarmStatus();
    }
  }

  Future<void> _checkAlarmStatus() async {
    final isRinging = await AlarmService.isAlarmRinging();

    if (isRinging && mounted) {
      final alarm = await AlarmService.getActiveAlarm();
      if (alarm != null) {
        // Navigate to ringing screen (pass the alarm object)
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => AlarmRingingScreen(alarm: alarm),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}

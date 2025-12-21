import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:file_picker/file_picker.dart';

import '../models/alarm_model.dart';
import '../services/alarm_service.dart';
import '../screens/alarm_ringing_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<AlarmModel> alarms = [];
  bool _navigatedToAlarm = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAlarms();
    _startRingingWatcher();
    _listenToAlarmChanges();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkForRingingAlarm();
    }
  }

  // Listen to alarm changes via stream
  void _listenToAlarmChanges() {
    AlarmService.alarmsStream.listen((updatedAlarms) {
      if (mounted) {
        setState(() => alarms = updatedAlarms);
      }
    });
  }

  void _startRingingWatcher() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));

      if (!mounted || _navigatedToAlarm) return false;

      await _checkForRingingAlarm();
      
      return mounted;
    });
  }

  Future<void> _checkForRingingAlarm() async {
    if (await AlarmService.isAlarmRinging()) {
      final alarm = await AlarmService.getActiveAlarm();
      if (alarm != null && mounted && !_navigatedToAlarm) {
        _navigatedToAlarm = true;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AlarmRingingScreen(alarm: alarm),
          ),
        ).then((_) {
          _navigatedToAlarm = false;
        });
      }
    }
  }

  Future<void> _loadAlarms() async {
    final loaded = await AlarmService.getAllAlarms();
    if (!mounted) return;
    setState(() => alarms = loaded);
  }

  Future<DateTime?> _pickCircularTime() async {
    DateTime selected = DateTime.now();

    return showModalBottomSheet<DateTime>(
      context: context,
      builder: (_) {
        return SizedBox(
          height: 260,
          child: Column(
            children: [
              SizedBox(
                height: 180,
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: false,
                  initialDateTime: selected,
                  onDateTimeChanged: (dt) => selected = dt,
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, selected),
                child: const Text("Set Time"),
              )
            ],
          ),
        );
      },
    );
  }

  Future<void> _addAlarm() async {
    final pickedTime = await _pickCircularTime();
    if (pickedTime == null) return;

    final passwordController = TextEditingController();
    String? chosenSoundPath;

    final password = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (c, setInner) {
          return AlertDialog(
            title: const Text("Set Password & Sound"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: "Enter password",
                    helperText: "Required to stop alarm",
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        final res = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['mp3', 'wav', 'm4a', 'ogg'],
                        );
                        if (res != null) {
                          chosenSoundPath = res.files.single.path;
                          setInner(() {});
                        }
                      },
                      child: const Text("Pick Sound"),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        chosenSoundPath == null
                            ? "Default"
                            : chosenSoundPath!
                                .split(Platform.pathSeparator)
                                .last,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    )
                  ],
                )
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () {
                  if (passwordController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Password is required!')),
                    );
                    return;
                  }
                  Navigator.pop(context, passwordController.text);
                },
                child: const Text("Set"),
              ),
            ],
          );
        });
      },
    );

    if (password == null || password.isEmpty) return;

    final now = DateTime.now();
    var alarmTime = DateTime(
      now.year,
      now.month,
      now.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    // If time is in the past, schedule for tomorrow
    if (alarmTime.isBefore(now)) {
      alarmTime = alarmTime.add(const Duration(days: 1));
    }

    // Generate a safe ID (32-bit integer)
    final alarm = AlarmModel(
      id: DateTime.now().millisecondsSinceEpoch % 2147483647, // Max 32-bit int
      time: alarmTime,
      password: password,
      isActive: true,
      soundPath: chosenSoundPath,
    );

    // Schedule alarm - this will automatically update UI via stream
    await AlarmService.scheduleAlarm(alarm);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Alarm set for ${_formatTime(alarmTime)}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteAlarm(int id) async {
    // This will automatically update UI via stream
    await AlarmService.cancelAlarm(id);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alarm deleted')),
      );
    }
  }

  String _formatTime(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Password Alarm"),
      ),
      body: alarms.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.alarm_off, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    "No alarms set",
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Tap + to add an alarm",
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: alarms.length,
              itemBuilder: (context, index) {
                final alarm = alarms[index];
                final now = DateTime.now();
                final isToday = alarm.time.day == now.day &&
                    alarm.time.month == now.month &&
                    alarm.time.year == now.year;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade100,
                      child: const Icon(Icons.alarm, color: Colors.blue),
                    ),
                    title: Text(
                      _formatTime(alarm.time),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isToday ? 'Today' : 'Tomorrow'),
                        if (alarm.soundPath != null)
                          Text(
                            alarm.soundPath!.split(Platform.pathSeparator).last,
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          )
                        else
                          Text(
                            'Default sound',
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteAlarm(alarm.id),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addAlarm,
        icon: const Icon(Icons.add),
        label: const Text("Add Alarm"),
      ),
    );
  }
}
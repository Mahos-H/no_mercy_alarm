import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/alarm_model.dart';
import '../services/alarm_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<AlarmModel> alarms = [];
  StreamSubscription<List<AlarmModel>>? _alarmsSub;

  int? _activeAlarmId;
  Timer? _activePoll;

  static const _activePollInterval = Duration(seconds: 1);

  @override
  void initState() {
    super.initState();
    _loadAlarms();
    _listenToAlarmChanges();
    _startActiveAlarmPolling();
  }

  void _listenToAlarmChanges() {
    _alarmsSub?.cancel();
    _alarmsSub = AlarmService.alarmsStream.listen((updatedAlarms) {
      if (mounted) {
        setState(() => alarms = updatedAlarms);
      }
    });
  }

  void _startActiveAlarmPolling() {
    _activePoll?.cancel();

    // One immediate fetch so UI disables delete quickly.
    _refreshActiveAlarmId();

    _activePoll = Timer.periodic(_activePollInterval, (_) {
      _refreshActiveAlarmId();
    });
  }

  Future<void> _refreshActiveAlarmId() async {
    final id = await AlarmService.getActiveAlarmId();
    if (!mounted) return;

    if (id != _activeAlarmId) {
      setState(() => _activeAlarmId = id);
    }
  }

  @override
  void dispose() {
    _activePoll?.cancel();
    _alarmsSub?.cancel();
    super.dispose();
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

  int _hashToPositive31Bit(String s) {
    int hash = 0x811C9DC5;
    for (final unit in s.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }

  Future<int> _generateAlarmId(DateTime alarmTime) async {
    final keyStr =
        '${alarmTime.year.toString().padLeft(4, '0')}-'
        '${alarmTime.month.toString().padLeft(2, '0')}-'
        '${alarmTime.day.toString().padLeft(2, '0')}T'
        '${alarmTime.hour.toString().padLeft(2, '0')}:'
        '${alarmTime.minute.toString().padLeft(2, '0')}';

    var id = _hashToPositive31Bit(keyStr);

    while (await AlarmService.getAlarmById(id) != null) {
      id = (id + 1) & 0x7FFFFFFF;
      if (id == 0) id = 1;
    }

    return id;
  }

  bool _sameMinute(DateTime a, DateTime b) {
    return a.year == b.year &&
        a.month == b.month &&
        a.day == b.day &&
        a.hour == b.hour &&
        a.minute == b.minute;
  }

  Future<void> _addAlarm() async {
    final pickedTime = await _pickCircularTime();
    if (pickedTime == null) return;
    if (!mounted) return;
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

    if (alarmTime.isBefore(now)) {
      alarmTime = alarmTime.add(const Duration(days: 1));
    }

    final existing = alarms.any((a) => _sameMinute(a.time, alarmTime));
    if (existing) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An alarm is already set for ${_formatTime(alarmTime)}.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final id = await _generateAlarmId(alarmTime);

    final alarm = AlarmModel(
      id: id,
      time: alarmTime,
      password: password,
      isActive: true,
      soundPath: chosenSoundPath,
    );

    try {
      await AlarmService.scheduleAlarm(alarm);
    } on StateError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Alarm set for ${_formatTime(alarmTime)}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteAlarm(AlarmModel alarm) async {
    // Option C enforcement: prevent deleting the active alarm.
    if (_activeAlarmId != null && alarm.id == _activeAlarmId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This alarm is currently ringing and cannot be deleted.')),
        );
      }
      return;
    }

    await AlarmService.cancelAlarm(alarm.id);

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
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'clear_data') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clear All Data?'),
                    content: const Text(
                      'This will remove all alarms and reset the app. Use this if you\'re experiencing issues.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('Clear All'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await AlarmService.clearAllData();
                  await _loadAlarms();
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(content: Text('All data cleared')),
                  );

                  
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear_data',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Clear All Data'),
                  ],
                ),
              ),
            ],
          ),
        ],
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

                final isActive = _activeAlarmId != null && alarm.id == _activeAlarmId;

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
                        if (isActive)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'RINGING',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.delete, color: isActive ? Colors.grey : Colors.red),
                      onPressed: () => _deleteAlarm(alarm),
                      // (we still route through _deleteAlarm so it can show snackbar)
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
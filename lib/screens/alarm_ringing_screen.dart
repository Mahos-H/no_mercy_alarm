import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alarm_model.dart';
import '../services/alarm_service.dart';

class AlarmRingingScreen extends StatefulWidget {
  final AlarmModel alarm;
  const AlarmRingingScreen({super.key, required this.alarm});

  @override
  State<AlarmRingingScreen> createState() => _AlarmRingingScreenState();
}

class _AlarmRingingScreenState extends State<AlarmRingingScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  String error = '';

  double _sliderValue = 0.0;
  bool _sliderCompleted = false;

  late AnimationController _pulseController;

  int? _firstWrongAtMs;
  bool _showPassword = false;

  static const _revealDelayMs = 120000; // 120 seconds

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _loadFirstWrongAt();
  }

  @override
  void dispose() {
    _controller.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadFirstWrongAt() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt('alarm_${widget.alarm.id}_first_wrong_at_ms');
    if (mounted) {
      setState(() => _firstWrongAtMs = v);
    }
  }

  Future<void> _recordFirstWrongIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'alarm_${widget.alarm.id}_first_wrong_at_ms';
    final existing = prefs.getInt(key);
    if (existing != null) {
      _firstWrongAtMs = existing;
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt(key, now);
    _firstWrongAtMs = now;
  }

  bool get _revealAllowed {
    if (_firstWrongAtMs == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - _firstWrongAtMs!) >= _revealDelayMs;
  }

  String _revealCountdownText() {
    if (_firstWrongAtMs == null) return '';
    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining = _revealDelayMs - (now - _firstWrongAtMs!);
    if (remaining <= 0) return 'You can reveal the password now.';
    final seconds = (remaining / 1000).ceil();
    final mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (seconds % 60).toString().padLeft(2, '0');
    return 'Reveal available in $mm:$ss';
  }

  Future<void> _stop() async {
    if (!_sliderCompleted) {
      setState(() => error = "Please slide to unlock first");
      return;
    }

    if (_controller.text.isEmpty) {
      setState(() => error = "Please enter password");
      return;
    }

    if (_controller.text != widget.alarm.password) {
      await _recordFirstWrongIfNeeded();
      setState(() {
        error = "Wrong password!";
        _sliderValue = 0.0;
        _sliderCompleted = false;
        _showPassword = false;
      });
      return;
    }

    setState(() => error = "");
    await _showSuccessAndClose();
  }

  Future<void> _showSuccessAndClose() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(40),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.green.shade700,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withOpacity(0.5),
                  blurRadius: 20,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: Colors.white,
                  size: 80,
                ),
                SizedBox(height: 16),
                Text(
                  "Alarm Stopped!",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "Have a great day!",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await Future.delayed(const Duration(seconds: 2));

    await AlarmService.stopAlarmAndCleanup(alarmId: widget.alarm.id);

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // success dialog
      Navigator.of(context, rootNavigator: true).pop(); // ringing screen
    }
  }

  @override
  Widget build(BuildContext context) {
    final revealAllowed = _revealAllowed;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.red.shade900,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.red.shade900,
                Colors.red.shade700,
                Colors.red.shade900,
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: 1.0 + (_pulseController.value * 0.2),
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.3),
                                  blurRadius: 20,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.alarm,
                              size: 100,
                              color: Colors.white,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                    Text(
                      "ALARM!",
                      style: TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.5),
                            offset: const Offset(2, 2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}",
                      style: const TextStyle(
                        fontSize: 32,
                        color: Colors.white70,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Slider to unlock
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _sliderCompleted
                                ? "✓ Unlocked - Enter password"
                                : "Slide to unlock →",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 60,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 30,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 40,
                              ),
                              activeTrackColor: Colors.green,
                              inactiveTrackColor: Colors.white.withOpacity(0.3),
                              thumbColor: Colors.white,
                            ),
                            child: Slider(
                              value: _sliderValue,
                              min: 0.0,
                              max: 100.0,
                              onChanged: _sliderCompleted
                                  ? null
                                  : (value) {
                                      setState(() {
                                        _sliderValue = value;
                                        if (value >= 95.0) {
                                          _sliderCompleted = true;
                                          _sliderValue = 100.0;
                                        }
                                      });
                                    },
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Password container
                    AnimatedOpacity(
                      opacity: _sliderCompleted ? 1.0 : 0.3,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: _controller,
                              obscureText: true,
                              enabled: _sliderCompleted,
                              autofocus: _sliderCompleted,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 4,
                              ),
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                hintText: "Enter Password",
                                hintStyle: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 18,
                                ),
                                border: InputBorder.none,
                                errorText: error.isEmpty ? null : error,
                                errorStyle: const TextStyle(
                                  color: Colors.yellow,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onSubmitted:
                                  _sliderCompleted ? (_) => _stop() : null,
                            ),
                            const SizedBox(height: 16),

                            if (_firstWrongAtMs != null) ...[
                              Text(
                                _revealCountdownText(),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (revealAllowed)
                                OutlinedButton(
                                  onPressed: () {
                                    setState(() => _showPassword = !_showPassword);
                                  },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.white70),
                                  ),
                                  child: Text(_showPassword
                                      ? "Hide password"
                                      : "Reveal password"),
                                ),
                              if (revealAllowed && _showPassword)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    widget.alarm.password,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],

                            const SizedBox(height: 12),

                            SizedBox(
                              width: double.infinity,
                              height: 60,
                              child: ElevatedButton(
                                onPressed: _sliderCompleted ? _stop : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.red.shade900,
                                  disabledBackgroundColor:
                                      Colors.white.withOpacity(0.3),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                child: const Text("STOP ALARM"),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
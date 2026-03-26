import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/alarm_model.dart';
import '../services/alarm_service.dart';

class AlarmRingingScreen extends StatefulWidget {
  final AlarmModel alarm;
  const AlarmRingingScreen({Key? key, required this.alarm}) : super(key: key);

  @override
  State<AlarmRingingScreen> createState() => _AlarmRingingScreenState();
}

class _AlarmRingingScreenState extends State<AlarmRingingScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _player = AudioPlayer();
  String error = '';
  bool _isPlaying = false;
  double _sliderValue = 0.0;
  bool _sliderCompleted = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _play();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _player.dispose();
    _controller.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);

      if (widget.alarm.soundPath != null &&
          File(widget.alarm.soundPath!).existsSync()) {
        await _player.play(DeviceFileSource(widget.alarm.soundPath!));
      } else {
        await _player.play(AssetSource('sounds/alarm_sound.mp3'));
      }

      setState(() => _isPlaying = true);
      print('🔊 Alarm sound playing');
    } catch (e) {
      print('⚠️ Error playing alarm sound: $e');
    }
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
      setState(() {
        error = "Wrong password!";
        _sliderValue = 0.0;
        _sliderCompleted = false;
      });
      return;
    }

    print('✅ Correct password entered - stopping alarm');

    // Stop the sound
    await _player.stop();
    
    // Show success message
    setState(() => error = "");
    
    // Show success animation
    await _showSuccessAndClose();
  }

  Future<void> _showSuccessAndClose() async {
    // Show success dialog
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: Colors.white,
                  size: 80,
                ),
                const SizedBox(height: 16),
                const Text(
                  "Alarm Stopped!",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
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

    // Wait a moment
    await Future.delayed(const Duration(seconds: 2));

    // Stop the alarm service
    await AlarmService.stopAlarm();

    // Close everything and go back to home
    if (mounted) {
      // Pop the success dialog
      Navigator.of(context, rootNavigator: true).pop();
      // Pop the ringing screen
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    // Pulsing alarm icon
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

                    // ALARM text with shadow
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

                    // Time display
                    Text(
                      "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}",
                      style: const TextStyle(
                        fontSize: 32,
                        color: Colors.white70,
                        fontWeight: FontWeight.w300,
                      ),
                    ),

                    if (_isPlaying)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.volume_up, color: Colors.white70, size: 20),
                            SizedBox(width: 8),
                            Text(
                              "Sound playing",
                              style: TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ],
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

                    // Password input (only visible after slider)
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
                              onSubmitted: _sliderCompleted ? (_) => _stop() : null,
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 60,
                              child: ElevatedButton(
                                onPressed: _sliderCompleted ? _stop : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.red.shade900,
                                  disabledBackgroundColor: Colors.white.withOpacity(0.3),
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
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_vibrate/flutter_vibrate.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeCallPage extends StatefulWidget {
  const FakeCallPage({super.key});

  @override
  _FakeCallPageState createState() => _FakeCallPageState();
}

class _FakeCallPageState extends State<FakeCallPage> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isCallAnswered = false;
  Duration _callDuration = Duration.zero;
  Timer? _timer;

  String callerName = "John Doe"; // Default name
  String language = "english"; // Default language

  @override
  void initState() {
    super.initState();
    _checkFirstTimeLaunch();
    _playRingtone();
    _startVibration();
  }

  // Check if it's the first time the app is launched
  void _checkFirstTimeLaunch() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool? isFirstTime = prefs.getBool('isFirstTime');
    
    if (isFirstTime == null || isFirstTime) {
      _showNameAndLanguageDialog();
    } else {
      setState(() {
        callerName = prefs.getString('callerName') ?? "John Doe";
        language = prefs.getString('language') ?? "english";
      });
    }
  }

  // Show a dialog to enter caller's name and select language
  void _showNameAndLanguageDialog() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    TextEditingController nameController = TextEditingController();
    String selectedLanguage = "english";

    // Show dialog to input caller's name and select language
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Enter Caller Name and Language'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Caller Name'),
              ),
              DropdownButton<String>(
                value: selectedLanguage,
                onChanged: (String? newValue) {
                  setState(() {
                    selectedLanguage = newValue!;
                  });
                },
                items: <String>['english', 'sinhala']
                    .map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                // Save the data to SharedPreferences
                prefs.setBool('isFirstTime', false);
                prefs.setString('callerName', nameController.text);
                prefs.setString('language', selectedLanguage);

                // Set the state with the user's input
                setState(() {
                  callerName = nameController.text;
                  language = selectedLanguage;
                });

                Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _playRingtone() async {
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('ringtone.mp3'));
  }

  void _startVibration() async {
    bool canVibrate = await Vibrate.canVibrate;
    if (canVibrate) {
      final pattern = [const Duration(milliseconds: 500), const Duration(milliseconds: 1000)];
      Vibrate.vibrateWithPauses(pattern);
    }
  }

  void _stopRingtoneAndVibration() {
    _audioPlayer.stop();
    // No need to cancel vibration manually
  }

  void _startCallTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _callDuration += const Duration(seconds: 1);
      });
    });
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(d.inMinutes)}:${twoDigits(d.inSeconds.remainder(60))}';
  }

  // Play the appropriate fake voice message based on language
  void _playFakeVoice() async {
    if (language == 'english') {
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.play(AssetSource('fake_voice_english.mp3'));
    } else if (language == 'sinhala') {
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      //await _audioPlayer.play(AssetSource('fake_voice_sinhala.mp3'));
    }
  }

  @override
  void dispose() {
    _stopRingtoneAndVibration();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircleAvatar(
              radius: 60,
              backgroundImage: AssetImage('assets/fake_caller.jpg'),
            ),
            const SizedBox(height: 20),
            Text(
              callerName,
              style: const TextStyle(color: Colors.black, fontSize: 30),
            ),
            Text(
              _isCallAnswered ? _formatDuration(_callDuration) : 'Incoming Call...',
              style: const TextStyle(color: Colors.black, fontSize: 18),
            ),
            const SizedBox(height: 50),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton(
                  backgroundColor: Colors.red,
                  onPressed: () {
                    _stopRingtoneAndVibration();
                    _timer?.cancel();
                    Navigator.pop(context);
                  },
                  child: const Icon(Icons.call_end),
                ),
                if (!_isCallAnswered)
                  FloatingActionButton(
                    backgroundColor: Colors.green,
                    onPressed: () async {
                      _stopRingtoneAndVibration();
                      _playFakeVoice();
                      setState(() {
                        _isCallAnswered = true;
                      });
                      _startCallTimer();
                    },
                    child: const Icon(Icons.call),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

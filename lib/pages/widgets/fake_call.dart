import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_vibrate/flutter_vibrate.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeCallPage extends StatefulWidget {
  const FakeCallPage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _FakeCallPageState createState() => _FakeCallPageState();
}

class _FakeCallPageState extends State<FakeCallPage> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isCallAnswered = false;
  bool _isSpeakerOn = false; // Added for speaker functionality
  Duration _callDuration = Duration.zero;
  Timer? _timer;

  String callerName = ""; // Default name
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
        callerName = prefs.getString('callerName') ?? "Unknown Caller";
        language = prefs.getString('language') ?? "english";
      });
    }
  }

  // Show a dialog to enter caller's name and select language
  void _showNameAndLanguageDialog() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    TextEditingController nameController = TextEditingController();
    String selectedLanguage = "english";

    await showDialog(
      // ignore: use_build_context_synchronously
      context: context,
      builder: (context) {
        return StatefulBuilder(  // Use StatefulBuilder to manage dialog state
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Enter Caller Name and Language'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Caller Name'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButton<String>(
                    value: selectedLanguage,
                    onChanged: (String? newValue) {
                      setDialogState(() {  // Use setDialogState instead of setState
                        selectedLanguage = newValue!;
                      });
                    },
                    items: <String>['english', 'sinhala']
                        .map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value.toUpperCase()), 
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
                    prefs.setString('callerName', nameController.text.isEmpty ? "Unknown Caller" : nameController.text);
                    prefs.setString('language', selectedLanguage);

                    // Set the state with the user's input
                    setState(() {
                      callerName = nameController.text.isEmpty ? "Unknown Caller" : nameController.text;
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

  // Toggle speaker mode
  void _toggleSpeaker() async {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
    

    if (_isSpeakerOn) {
      await _audioPlayer.setVolume(1.0); // Maximum 
    } else {
      await _audioPlayer.setVolume(0.5); // Normal 
    }
  }

  void _playFakeVoice() async {
    if (language == 'english') {
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.play(AssetSource('fake_voice_english.mp3'));
      
      if (_isSpeakerOn) {
        await _audioPlayer.setVolume(1.0);
      } else {
        await _audioPlayer.setVolume(0.5);
      }
    } else if (language == 'sinhala') {
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.play(AssetSource('fake_call_sinhala.mp3'));
      
      if (_isSpeakerOn) {
        await _audioPlayer.setVolume(1.0);
      } else {
        await _audioPlayer.setVolume(0.5);
      }
    }
  }

  @override
  void dispose() {
    _stopRingtoneAndVibration();
    _timer?.cancel();
    _audioPlayer.dispose(); 
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
                // Only show speaker button when the call is answered
                if (_isCallAnswered)
                  FloatingActionButton(
                    backgroundColor: _isSpeakerOn ? Colors.blue : Colors.grey,
                    onPressed: _toggleSpeaker,
                    child: const Icon(Icons.volume_up),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
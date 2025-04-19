import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_vibrate/flutter_vibrate.dart';

class FakeCallPage extends StatefulWidget {
  const FakeCallPage({Key? key}) : super(key: key);

  @override
  _FakeCallPageState createState() => _FakeCallPageState();
}

class _FakeCallPageState extends State<FakeCallPage> {
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _playRingtone();
    _startVibration();
  }

  void _playRingtone() async {
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('ringtone.mp3')); 
  }

  void _startVibration() async {
    bool canVibrate = await Vibrate.canVibrate;
    if (canVibrate) {
      final pattern = [Duration(milliseconds: 500), Duration(milliseconds: 1000)];
      Vibrate.vibrateWithPauses(pattern);
    }
  }

  void _stopRingtoneAndVibration() {
    _audioPlayer.stop();
    // No need to manually cancel vibration; it stops automatically in `flutter_vibrate`
  }

  @override
  void dispose() {
    _stopRingtoneAndVibration();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircleAvatar(
              radius: 60,
              backgroundImage: AssetImage('assets/fake_caller.jpg'),
            ),
            const SizedBox(height: 20),
            const Text(
              'John Doe',
              style: TextStyle(color: Colors.white, fontSize: 30),
            ),
            const Text(
              'Incoming Call...',
              style: TextStyle(color: Colors.white54, fontSize: 18),
            ),
            const SizedBox(height: 50),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton(
                  backgroundColor: Colors.red,
                  onPressed: () {
                    _stopRingtoneAndVibration();
                    Navigator.pop(context);
                  },
                  child: const Icon(Icons.call_end),
                ),
                FloatingActionButton(
                  backgroundColor: Colors.green,
                  onPressed: () {
                    _stopRingtoneAndVibration();
                    // You could show another screen here (like "ongoing call")
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

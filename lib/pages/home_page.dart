import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safe_pulse/pages/public_emergency/live_help.dart';
import 'package:safe_pulse/pages/public_emergency/public_emergency.dart';
import 'package:safe_pulse/db/db.dart';
import 'package:safe_pulse/model/contactdb.dart';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:intl/intl.dart';
import 'package:flutter_fgbg/flutter_fgbg.dart';
import 'package:video_player/video_player.dart';
import 'package:open_file/open_file.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DB _db = DB();
  List<Dcontacts> emergencyContacts = [];
  bool isSendingAlerts = false;
  bool isRecording = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  
  // Camera controller
  CameraController? _cameraController;
  List<CameraDescription> cameras = [];
  
  // Audio recorder
  final _audioRecorder = Record();
  String? _audioPath;
  String? _videoPath;

  // Power button detection
  int _powerButtonPressCount = 0;
  DateTime? _lastPowerButtonPress;
  static const int _maxTimeWindowMs = 2000;
  
  // App lifecycle
  late Stream<FGBGType> _fgbgStream;
  late StreamSubscription<FGBGType> _fgbgSubscription;

  @override
  void initState() {
    super.initState();
    _loadEmergencyContacts();
    _initCameras();
    _initPowerButtonDetection();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _audioRecorder.dispose();
    _recordingTimer?.cancel();
    _fgbgSubscription.cancel();
    super.dispose();
  }

  void _initPowerButtonDetection() {
    _fgbgStream = FGBGEvents.stream;
    _fgbgSubscription = _fgbgStream.listen((event) {
      _handlePowerButtonPress(event);
    });

    SystemChannels.lifecycle.setMessageHandler((msg) async {
      if (msg == AppLifecycleState.resumed.toString()) {
        _checkPowerButtonSequence();
      }
      return null;
    });
  }

  void _handlePowerButtonPress(FGBGType event) {
    if (event == FGBGType.background) {
      _checkPowerButtonSequence(isPowerOff: true);
    } else if (event == FGBGType.foreground) {
      _checkPowerButtonSequence();
    }
  }

  void _checkPowerButtonSequence({bool isPowerOff = false}) {
    final now = DateTime.now();
    
    if (_lastPowerButtonPress == null || 
        now.difference(_lastPowerButtonPress!).inMilliseconds > _maxTimeWindowMs) {
      _powerButtonPressCount = 1;
    } else {
      _powerButtonPressCount++;
    }
    
    _lastPowerButtonPress = now;
    
    if (_powerButtonPressCount >= 3) {
      _powerButtonPressCount = 0;
      _lastPowerButtonPress = null;
      
      if (!isSendingAlerts && !isRecording) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _sendEmergencyMessage();
        });
      }
    }
  }

  Future<void> _initCameras() async {
    try {
      cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        _initializeCamera();
      }
    } catch (e) {
      debugPrint('Error initializing cameras: $e');
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
      );
      
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> _loadEmergencyContacts() async {
    List<Dcontacts> contacts = await _db.getContacts();
    setState(() {
      emergencyContacts = contacts;
    });
  }

  Future<bool> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.sms,
      Permission.camera,
      Permission.microphone,
      Permission.storage,
      if (Platform.isAndroid) Permission.accessMediaLocation,
    ].request();
    
    return statuses[Permission.sms]!.isGranted &&
           statuses[Permission.camera]!.isGranted &&
           statuses[Permission.microphone]!.isGranted &&
           statuses[Permission.storage]!.isGranted;
  }

  Future<bool> _checkStoragePermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.status;
      if (!status.isGranted) {
        final result = await Permission.storage.request();
        return result.isGranted;
      }
    }
    return true;
  }

  Future<void> _startRecording() async {
    if (isRecording) return;
    
    if (!await _checkStoragePermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Storage permission required to save recordings"),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() {
      isRecording = true;
      _recordingDuration = Duration.zero;
    });

    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordingDuration += const Duration(seconds: 1);
      });
    });

    try {
      final directory = await getDownloadsDirectory();
      if (directory == null) {
        throw Exception('Could not access downloads directory');
      }

      final safePulseDir = Directory('${directory.path}/SafePulse');
      if (!await safePulseDir.exists()) {
        await safePulseDir.create();
      }

      final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      _videoPath = '${safePulseDir.path}/emergency_video_$now.mp4';
      _audioPath = '${safePulseDir.path}/emergency_audio_$now.m4a';
      
      // Start video recording
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        await _cameraController!.startVideoRecording();
        debugPrint('Video recording started');
      }
      
      // Start audio recording
      if (await _audioRecorder.hasPermission()) {
        await _audioRecorder.start(
          path: _audioPath,
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          samplingRate: 44100,
        );
        debugPrint('Audio recording started: $_audioPath');
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Emergency recording started"),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
      
      // Auto-stop after 5 minutes
      Future.delayed(const Duration(seconds: 300), () {
        if (isRecording) {
          _stopRecording();
        }
      });
      
    } catch (e) {
      debugPrint('Error starting recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to start recording: ${e.toString()}"),
            backgroundColor: Colors.orange,
          ),
        );
      }
      setState(() {
        isRecording = false;
        _recordingTimer?.cancel();
      });
    }
  }

 Future<void> _stopRecording() async {
  if (!isRecording) return;
  
  _recordingTimer?.cancel();
  
  try {
    // Stop video recording
    if (_cameraController != null && 
        _cameraController!.value.isInitialized &&
        _cameraController!.value.isRecordingVideo) {
      final videoFile = await _cameraController!.stopVideoRecording();
      
      // Get the downloads directory
      final directory = await getDownloadsDirectory();
      if (directory == null) {
        throw Exception('Could not access downloads directory');
      }
      
      // Create SafePulse folder if it doesn't exist
      final safePulseDir = Directory('${directory.path}/SafePulse');
      if (!await safePulseDir.exists()) {
        await safePulseDir.create();
      }
      
      // Generate a filename with timestamp
      final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final destFileName = 'emergency_video_$now.mp4';
      final destPath = '${safePulseDir.path}/$destFileName';
      
      // Save the file to the downloads directory
      await videoFile.saveTo(destPath);
      _videoPath = destPath;
      
      debugPrint('Video recording saved to: $_videoPath');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Recording saved to ${safePulseDir.path}"),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'VIEW',
              onPressed: () => _viewRecordedVideo(),
            ),
          ),
        );
      }
      
      // Send the recording to emergency contacts if needed
      if (emergencyContacts.isNotEmpty) {
        await _sendRecordingToContacts();
      }
    }
    
    // Stop audio recording
    if (await _audioRecorder.isRecording()) {
      await _audioRecorder.stop();
      debugPrint('Audio recording saved: $_audioPath');
    }
    
  } catch (e) {
    debugPrint('Error stopping recording: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error saving recording: ${e.toString()}"),
          backgroundColor: Colors.orange,
        ),
      );
    }
  } finally {
    setState(() {
      isRecording = false;
    });
  }
}

Future<String?> _saveFileWithPicker(XFile videoFile) async {
  try {
    // Create a temporary file first to have something to work with
    final tempDir = await getTemporaryDirectory();
    final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final tempPath = '${tempDir.path}/temp_emergency_video_$now.mp4';
    
    await videoFile.saveTo(tempPath);
    
    Directory? directory;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Save Emergency Recording'),
          content: const Text('Choose where to save your emergency recording:'),
          actions: <Widget>[
            TextButton(
              child: const Text('Downloads'),
              onPressed: () async {
                // Get downloads directory
                directory = await getDownloadsDirectory();
                Navigator.of(context).pop(true);
              },
            ),
            TextButton(
              child: const Text('Documents'),
              onPressed: () async {
                // Get documents directory
                directory = await getApplicationDocumentsDirectory();
                Navigator.of(context).pop(true);
              },
            ),
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
          ],
        );
      },
    );
    
    if (confirmed == true && directory != null) {
      // Generate a destination path
      String destFileName = 'emergency_video_$now.mp4';
      String destPath = '${directory!.path}/$destFileName';
      
      // Copy from temp to destination
      await File(tempPath).copy(destPath);
      
      // Show where it was saved
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to ${directory!.path}'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      return destPath;
    }
    
    return null;
  } catch (e) {
    debugPrint('Error saving file: $e');
    return null;
  }
}
Future<void> _sendRecordingToContacts() async {
  if (!await _requestPermissions()) {
    debugPrint("Required permissions denied");
    return;
  }

  setState(() {
    isSendingAlerts = true;
  });

  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Sending recording to emergency contacts..."),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 2),
      ),
    );
  }

  const String message = "🚨 EMERGENCY RECORDING 🚨\n"
      "Attached is the emergency recording from SafePulse app.\n"
      "Please check immediately!";

  int successfulSends = 0;
  int failedSends = 0;
  
  List<String> recipients = [];
  for (var contact in emergencyContacts) {
    final phoneNumber = contact.number.replaceAll(RegExp(r'[^0-9+]'), '');
    if (phoneNumber.isNotEmpty) {
      recipients.add(phoneNumber);
    }
  }
  
  try {
    //  for Android
    if (Platform.isAndroid) {
      final file = File(_videoPath!);
      if (await file.exists()) {
        final channel = const MethodChannel('safepulse/send_file');
        final result = await channel.invokeMethod('sendFile', {
          'filePath': _videoPath,
          'recipients': recipients,
          'message': message,
        });
        
        if (result == true) {
          successfulSends = recipients.length;
        } else {
          failedSends = recipients.length;
        }
      }
    } else {
      // For iOS
      debugPrint("Sending recordings is not supported on this platform");
      failedSends = recipients.length;
    }
  } catch (e) {
    debugPrint("Error sending recording: $e");
    failedSends = recipients.length;
  }

  setState(() {
    isSendingAlerts = false;
  });

  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          successfulSends > 0
            ? "Recording sent to $successfulSends contact(s)"
            : "Failed to send recording",
          style: const TextStyle(fontSize: 16),
        ),
        backgroundColor: successfulSends > 0 ? Colors.red : Colors.orange,
        duration: const Duration(seconds: 5),
        action: failedSends > 0
            ? SnackBarAction(
                label: 'Details',
                textColor: Colors.white,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to send to $failedSends contact(s)'),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                },
              )
            : null,
      ),
    );
  }
}

  Future<void> _viewRecordedVideo() async {
    if (_videoPath == null || !await File(_videoPath!).exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No video recorded yet")),
        );
      }
      return;
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text("Recorded Video")),
            body: Center(
              child: VideoPlayerWidget(videoPath: _videoPath!),
            ),
          ),
        ),
      );
    }
  }

  Future<void> _sendEmergencyMessage() async {
    if (emergencyContacts.isEmpty) {
      debugPrint("No emergency contacts to send to!");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No emergency contacts configured"),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (!await _requestPermissions()) {
      debugPrint("Required permissions denied");
      return;
    }

    setState(() {
      isSendingAlerts = true;
    });

    HapticFeedback.heavyImpact();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Sending emergency alerts..."),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }

    const String message = "🚨 EMERGENCY ALERT 🚨\n"
        "I need immediate help!\n"
        "This is an automated message from SafePulse app.\n"
        "Triggered by emergency power button sequence.";

    int successfulSends = 0;
    int failedSends = 0;
    
    List<String> recipients = [];
    for (var contact in emergencyContacts) {
      final phoneNumber = contact.number.replaceAll(RegExp(r'[^0-9+]'), '');
      if (phoneNumber.isNotEmpty) {
        recipients.add(phoneNumber);
      }
    }
    
    try {
      String result = await sendSMS(
        message: message,
        recipients: recipients,
        sendDirect: true,
      );
      
      if (result == "sent") {
        successfulSends = recipients.length;
      } else {
        successfulSends = recipients.length - failedSends;
        failedSends = recipients.length - successfulSends;
      }
    } catch (e) {
      debugPrint("Error sending SMS: $e");
      failedSends = recipients.length;
    }

    setState(() {
      isSendingAlerts = false;
    });

    HapticFeedback.mediumImpact();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            successfulSends > 0
              ? "Emergency alert sent to $successfulSends contact(s)"
              : "Failed to send emergency alerts",
            style: const TextStyle(fontSize: 16),
          ),
          backgroundColor: successfulSends > 0 ? Colors.red : Colors.orange,
          duration: const Duration(seconds: 5),
          action: failedSends > 0
              ? SnackBarAction(
                  label: 'Details',
                  textColor: Colors.white,
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to send to $failedSends contact(s)'),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  },
                )
              : null,
        ),
      );
    }
    
    if (successfulSends > 0) {
      await _startRecording();
    }
  }

  void _showEmergencyPopup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Emergency Contacts",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(),
              if (emergencyContacts.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text(
                      "No emergency contacts added",
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: emergencyContacts.length,
                    itemBuilder: (context, index) {
                      final contact = emergencyContacts[index];
                      final String initial = contact.name.isNotEmpty 
                          ? contact.name[0].toUpperCase()
                          : '?';
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.red[100],
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          contact.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(contact.number),
                      );
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: isSendingAlerts
                          ? null
                          : () {
                              Navigator.pop(context);
                              _sendEmergencyMessage();
                            },
                      child: isSendingAlerts
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              ),
                            )
                          : const Text(
                              "SEND EMERGENCY ALERT TO ALL",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                    const SizedBox(height: 8),
                    if (isRecording)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: _stopRecording,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              "STOP RECORDING",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecordingIndicator() {
    if (!isRecording) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.9),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withOpacity(0.5),
                  blurRadius: 4,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            "RECORDING",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              minimumSize: const Size(30, 30),
              padding: const EdgeInsets.all(5),
              shape: const CircleBorder(),
            ),
            onPressed: _stopRecording,
            child: const Icon(Icons.stop, color: Colors.red, size: 18),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Public Emergency Contacts",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const PublicEmergencyContacts(),
                    const SizedBox(height: 16),
                    const Text(
                      "Live Help",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const LiveHelp(),
                    const SizedBox(height: 8),
                    const Text(
                      "Emergency SOS",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: GestureDetector(
                        onTap: _showEmergencyPopup,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.5),
                                spreadRadius: 5,
                                blurRadius: 7,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              "SOS",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_cameraController != null && _cameraController!.value.isInitialized)
                      SizedBox(
                        height: 200,
                        child: CameraPreview(_cameraController!),
                      ),
                    if (isRecording) ...[
                      const SizedBox(height: 20),
                      Text(
                        "Recording: ${_recordingDuration.inMinutes}:${(_recordingDuration.inSeconds % 60).toString().padLeft(2, '0')}",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ],
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
            if (isRecording)
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: _buildRecordingIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class VideoPlayerWidget extends StatefulWidget {
  final String videoPath;

  const VideoPlayerWidget({super.key, required this.videoPath});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
        _isPlaying = true;
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _isPlaying = false;
      } else {
        _controller.play();
        _isPlaying = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(_controller),
              if (!_controller.value.isInitialized)
                const CircularProgressIndicator(),
              if (_controller.value.isInitialized)
                IconButton(
                  icon: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 50,
                    color: Colors.white,
                  ),
                  onPressed: _togglePlay,
                ),
            ],
          ),
        ),
        VideoProgressIndicator(
          _controller,
          allowScrubbing: true,
          colors: const VideoProgressColors(
            playedColor: Colors.red,
            bufferedColor: Colors.grey,
            backgroundColor: Colors.black26,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.open_in_new),
              onPressed: () => OpenFile.open(widget.videoPath),
              tooltip: 'Open in system player',
            ),
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () {
                // Implement share functionality
              },
              tooltip: 'Share video',
            ),
          ],
        ),
      ],
    );
  }
}
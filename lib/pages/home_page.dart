import 'dart:async';
import 'dart:convert';
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
import 'package:video_player/video_player.dart';
import 'package:open_file/open_file.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
  import 'package:share_plus/share_plus.dart';


// Callback dispatcher for WorkManager
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) {
    // This will be called when the notification button is pressed
    return Future.value(true);
  });
}

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
  bool _isEmergencyModeOn = false;
  
  // Camera controller
  CameraController? _cameraController;
  List<CameraDescription> cameras = [];
  
  // Audio recorder
  final _audioRecorder = Record();
  String? _audioPath;
  String? _videoPath;

  // Notifications
  final FlutterLocalNotificationsPlugin _notificationsPlugin = 
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _loadEmergencyContacts();
    _initCameras();
    _initializeNotifications();
    _initializeWorkManager();
    _loadEmergencyModeStatus();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _audioRecorder.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    
    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload == 'emergency_alert') {
          _sendEmergencyMessage();
        }
      },
    );
  }

  Future<void> _initializeWorkManager() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
  }

  Future<void> _loadEmergencyModeStatus() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isEmergencyModeOn = prefs.getBool('emergency_mode') ?? false;
    });
    
    if (_isEmergencyModeOn) {
      _showEmergencyModeNotification();
    }
  }

  Future<void> _toggleEmergencyMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('emergency_mode', value);
    
    const platform = MethodChannel('safepulse/emergency');
    try {
        if (value) {
            await platform.invokeMethod('startEmergencyService');
        } else {
            await platform.invokeMethod('stopEmergencyService');
        }
    } catch (e) {
        debugPrint('Error toggling emergency service: $e');
    }
    
    setState(() {
        _isEmergencyModeOn = value;
    });
    
    if (value) {
        _showEmergencyModeNotification();
    } else {
        _notificationsPlugin.cancel(0);
    }
  }

  Future<void> _showEmergencyModeNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'emergency_channel',
      'Emergency Mode',
      channelDescription: 'Emergency alert notifications',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
      ongoing: true,
      visibility: NotificationVisibility.public,
      fullScreenIntent: true,
      actions: [
        AndroidNotificationAction(
          'emergency_action',
          'SEND ALERT',
          showsUserInterface: true,
        ),
      ],
    );
    
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    
    await _notificationsPlugin.show(
      0,
      'Emergency Mode Active',
      'Tap to send emergency alert',
      platformChannelSpecifics,
      payload: 'emergency_alert',
    );
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
  
  final prefs = await SharedPreferences.getInstance();
  final contactsJson = jsonEncode(contacts.map((c) => {
    'name': c.name,
    'number': c.number.replaceAll(RegExp(r'[^0-9+]'), ''),
  }).toList());
  await prefs.setString('emergency_contacts', contactsJson);
}

Future<void> _storeEmergencyContacts() async {
  final contacts = await _db.getContacts();
  final prefs = await SharedPreferences.getInstance();
  final contactsJson = jsonEncode(contacts.map((c) => {
    'name': c.name,
    'number': c.number.replaceAll(RegExp(r'[^0-9+]'), ''),
  }).toList());
  await prefs.setString('emergency_contacts', contactsJson);
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
        
        final safePulseDir = Directory('${directory.path}/SafePulse');
        if (!await safePulseDir.exists()) {
          await safePulseDir.create();
        }
        
        final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
        final destFileName = 'emergency_video_$now.mp4';
        final destPath = '${safePulseDir.path}/$destFileName';
        
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
        content: Text("Preparing emergency recording for sharing..."),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 2),
      ),
    );
  }

  const String message = "🚨 EMERGENCY RECORDING 🚨\n"
      "Attached is the emergency recording from SafePulse app.\n"
      "Please check immediately!";

  try {
    final file = File(_videoPath!);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Recording file not found"),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final shouldShare = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Share Emergency Recording"),
        content: const Text("This will open your device's share sheet to send the recording."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Continue"),
          ),
        ],
      ),
    ) ?? false;

    if (!shouldShare) {
      debugPrint("User cancelled sharing");
      return;
    }

    // Get the result of the share action
    final shareResult = await Share.shareXFiles(
      [XFile(_videoPath!)],
      text: message,
      subject: 'Emergency Recording',
    ).then((_) => true).catchError((e) {
      debugPrint("Share error: $e");
      return false;
    });

    if (shareResult && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Recording shared successfully"),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    }
  } catch (e) {
    debugPrint("Error sharing recording: $e");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to share: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  } finally {
    setState(() {
      isSendingAlerts = false;
    });
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
        "This is an automated message from SafePulse app.\n";

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

  Widget _buildEmergencyModeSwitch() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            "Emergency Mode:",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Switch(
            value: _isEmergencyModeOn,
            onChanged: _toggleEmergencyMode,
            activeColor: Colors.red,
            activeTrackColor: Colors.red.withOpacity(0.5),
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
                    _buildEmergencyModeSwitch(),
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
import 'package:flutter/material.dart';
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
  
  // Camera controller
  CameraController? _cameraController;
  List<CameraDescription> cameras = [];
  
  // Audio recorder
  final _audioRecorder = Record();
  String? _audioPath;
  String? _videoPath;

  @override
  void initState() {
    super.initState();
    _loadEmergencyContacts();
    _initCameras();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _initCameras() async {
    try {
      cameras = await availableCameras();
    } catch (e) {
      debugPrint('Error initializing cameras: $e');
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
    ].request();
    
    return statuses[Permission.sms]!.isGranted &&
           statuses[Permission.camera]!.isGranted &&
           statuses[Permission.microphone]!.isGranted &&
           statuses[Permission.storage]!.isGranted;
  }

  Future<void> _startRecording() async {
    if (isRecording) return;
    
    setState(() {
      isRecording = true;
    });

    try {
      // Initialize camera if needed
      if (_cameraController == null && cameras.isNotEmpty) {
        _cameraController = CameraController(
          cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.back,
            orElse: () => cameras.first,
          ),
          ResolutionPreset.medium,
          enableAudio: false, // Audio handled separately
        );
        
        await _cameraController!.initialize();
      }
      
      // Generate timestamp for filenames
      final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final directory = await getApplicationDocumentsDirectory();
      
      // Start video recording
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        _videoPath = '${directory.path}/emergency_video_$now.mp4';
        await _cameraController!.startVideoRecording();
        debugPrint('Video recording started: $_videoPath');
      }
      
      // Start audio recording
      if (await _audioRecorder.hasPermission()) {
        _audioPath = '${directory.path}/emergency_audio_$now.m4a';
        await _audioRecorder.start(
          path: _audioPath,
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          samplingRate: 44100,
        );
        debugPrint('Audio recording started: $_audioPath');
      }
      
      // Show recording indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Emergency recording started"),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      
      // Automatic stop after 5 minutes (300 seconds)
      Future.delayed(const Duration(seconds: 300), () {
        if (isRecording) {
          _stopRecording();
        }
      });
      
    } catch (e) {
      debugPrint('Error starting recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to start recording: ${e.toString()}"),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
      setState(() {
        isRecording = false;
      });
    }
  }

  Future<void> _stopRecording() async {
    if (!isRecording) return;
    
    try {
      // Stop video recording
      if (_cameraController != null && 
          _cameraController!.value.isInitialized &&
          _cameraController!.value.isRecordingVideo) {
        final videoFile = await _cameraController!.stopVideoRecording();
        debugPrint('Video recording saved: ${videoFile.path}');
      }
      
      // Stop audio recording
      if (await _audioRecorder.isRecording()) {
        await _audioRecorder.stop();
        debugPrint('Audio recording saved: $_audioPath');
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Emergency recording saved"),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      debugPrint('Error stopping recording: $e');
    } finally {
      setState(() {
        isRecording = false;
      });
    }
  }

  Future<void> _sendEmergencyMessage() async {
    // Check if there are any emergency contacts
    if (emergencyContacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No emergency contacts to send to!"),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Request permissions
    if (!await _requestPermissions()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Required permissions denied. Cannot send emergency alerts or record."),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      isSendingAlerts = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Sending emergency alerts..."),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 2),
      ),
    );

    const String message = "🚨 EMERGENCY ALERT 🚨\n"
        "I need immediate help!\n"
        "This is an automated message from SafePulse app.";

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
        sendDirect: true, // Attempts to send without user interaction
      );
      
      if (result == "sent") {
        successfulSends = recipients.length;
      } else {
        // Some platforms may return partial success information
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
    
    // Start recording after sending alerts
    if (successfulSends > 0) {
      _startRecording();
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
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Stack(
            children: [
              SingleChildScrollView(
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
                    const SizedBox(height: 30),
                    if (isRecording)
                      Container(
                        margin: const EdgeInsets.only(top: 20),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red, width: 1),
                        ),
                        child: Column(
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.videocam, color: Colors.red),
                                SizedBox(width: 8),
                                Text(
                                  "Emergency Recording Active",
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "Video and audio recording in progress. This will automatically stop after 5 minutes or when you press stop.",
                              style: TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: _stopRecording,
                              child: const Text(
                                "STOP RECORDING",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              // Floating recording indicator
              if (isRecording)
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _buildRecordingIndicator(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
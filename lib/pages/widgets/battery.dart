import 'dart:async';
import 'package:flutter/material.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:safe_pulse/db/db.dart';
import 'package:safe_pulse/model/contactdb.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BatteryMonitorPage extends StatefulWidget {
  const BatteryMonitorPage({super.key});

  @override
  State<BatteryMonitorPage> createState() => _BatteryMonitorPageState();
}

class _BatteryMonitorPageState extends State<BatteryMonitorPage> {
  final Battery _battery = Battery();
  int _batteryLevel = 100;
  bool _isMonitoring = false;
  bool _alertSent = false;
  List<Dcontacts> _emergencyContacts = [];
  final DB _db = DB();
  bool _isDisposed = false;
  StreamSubscription<BatteryState>? _batteryStateSubscription;
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final Logger _logger = Logger();
  
  // New variables for auto-sending
  int _thresholdLevel = 50; // Default threshold
  Timer? _autoSendTimer;
  bool _autoSendEnabled = true;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _requestPermissions().then((_) {
      _loadEmergencyContacts();
      _loadSettings();
      _initBatteryMonitoring();
      _initBackgroundTask();
      _startAutoSendTimer(); // Start the timer for auto-sending
    });
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _safeSetState(() {
        _thresholdLevel = prefs.getInt('thresholdLevel') ?? 50;
        _autoSendEnabled = prefs.getBool('autoSendEnabled') ?? true;
      });
    } catch (e) {
      _logger.e("Failed to load settings", error: e);
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('thresholdLevel', _thresholdLevel);
      await prefs.setBool('autoSendEnabled', _autoSendEnabled);
    } catch (e) {
      _logger.e("Failed to save settings", error: e);
    }
  }

  void _startAutoSendTimer() {
    // Cancel existing timer if any
    _autoSendTimer?.cancel();
    
    // Create a new timer that checks battery level more frequently
    _autoSendTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (_isDisposed || !_autoSendEnabled) return;
      
      _battery.batteryLevel.then((level) {
        _safeSetState(() {
          _batteryLevel = level;
        });
        _checkBatteryLevel(level);
      });
    });
  }

  Future<void> _initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    
    await _notifications.initialize(initializationSettings);
  }

  Future<void> _requestPermissions() async {
    // Request SMS permission
    if (!await Permission.sms.status.isGranted) {
      await Permission.sms.request();
    }

    // Request notification permission
    if (!await Permission.notification.status.isGranted) {
      await Permission.notification.request();
    }

    // Request to ignore battery optimizations
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
      if (await Permission.ignoreBatteryOptimizations.isPermanentlyDenied) {
        await openAppSettings();
      }
    }
  }

  Future<void> _showNotification(String title, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'battery_channel',
      'Battery Alerts',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: false,
      ongoing: false,
      channelShowBadge: true,
      enableVibration: true,
    );
    
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    
    await _notifications.show(
      0,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _batteryStateSubscription?.cancel();
    _autoSendTimer?.cancel();
    AndroidAlarmManager.cancel(0);
    super.dispose();
  }

  Future<void> _loadEmergencyContacts() async {
    try {
      List<Dcontacts> contacts = await _db.getContacts();
      if (!mounted) return;
      setState(() {
        _emergencyContacts = contacts;
      });
    } catch (e) {
      _logger.e("Failed to load contacts", error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load emergency contacts')),
        );
      }
    }
  }

  Future<void> _initBatteryMonitoring() async {
    try {
      _batteryLevel = await _battery.batteryLevel;
      
      _batteryStateSubscription = _battery.onBatteryStateChanged.listen((BatteryState state) async {
        final currentLevel = await _battery.batteryLevel;
        _safeSetState(() {
          _batteryLevel = currentLevel;
        });
        
        if (state == BatteryState.discharging) {
          _startBatteryMonitoring();
        } else {
          _safeSetState(() {
            _alertSent = false;
          });
        }
        _checkBatteryLevel(currentLevel);
      });

      // Immediate check on initialization
      _checkBatteryLevel(_batteryLevel);
    } catch (e) {
      _logger.e("Battery monitoring initialization failed", error: e);
    }
  }

  void _startBatteryMonitoring() {
    _safeSetState(() {
      _isMonitoring = true;
    });
    _checkBatteryLevel(_batteryLevel);
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) {
      setState(fn);
    }
  }

  Future<void> _checkBatteryLevel(int level) async {
    if (_autoSendEnabled && level <= _thresholdLevel && !_alertSent && _emergencyContacts.isNotEmpty) {
      await _sendLowBatteryAlert();
      _safeSetState(() {
        _alertSent = true;
      });
      
      // Reset the alert sent flag after some time to allow for another alert
      // if the battery continues to drain
      Future.delayed(const Duration(hours: 1), () {
        if (!_isDisposed) {
          _safeSetState(() {
            _alertSent = false;
          });
        }
      });
    }
  }

  Future<void> _sendLowBatteryAlert() async {
    try {
      String message = "Emergency: My phone battery is critically low ($_batteryLevel%). "
          "I may not be able to respond soon. Please check on me if you don't hear from me.";

      List<String> recipients = _emergencyContacts.map((contact) => contact.number).toList();

      await sendSMS(
        message: message,
        recipients: recipients,
        sendDirect: true,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Low battery alert sent to emergency contacts')),
        );
      }
      
      await _showNotification('Emergency Alert Sent', 'Low battery notification sent to your contacts');
      _logger.i('Low battery alert sent to contacts');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send alert: ${e.toString()}')),
        );
      }
      await _showNotification('Alert Failed', 'Failed to send low battery alert');
      _logger.e('Failed to send low battery alert', error: e);
    }
  }

  Future<void> _initBackgroundTask() async {
    try {
      // Initialize AndroidAlarmManager
      await AndroidAlarmManager.initialize();
      
      // Cancel any existing alarms
      await AndroidAlarmManager.cancel(0);
      
      // Register the periodic task
      await AndroidAlarmManager.periodic(
        const Duration(minutes: 5), // More frequent checks
        0, // Unique ID
        _checkBatteryInBackground,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
        allowWhileIdle: true, // Important for Doze mode
      );
      
      _logger.i("Background task initialized successfully");
    } catch (e) {
      _logger.e("Failed to initialize background task", error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to setup background monitoring')),
        );
      }
    }
  }

  @pragma('vm:entry-point')
  static Future<void> _checkBatteryInBackground() async {
    final logger = Logger();
    try {
      // Get shared preferences to access settings
      final prefs = await SharedPreferences.getInstance();
      final thresholdLevel = prefs.getInt('thresholdLevel') ?? 50;
      final autoSendEnabled = prefs.getBool('autoSendEnabled') ?? true;
      
      if (!autoSendEnabled) {
        logger.i("Auto-send is disabled. Skipping background check.");
        return;
      }
      
      // Acquire wake lock to keep device awake during task
      await WakelockPlus.enable();
      
      final battery = Battery();
      final level = await battery.batteryLevel;
      final state = await battery.batteryState;

      logger.i("Background check - Battery level: $level%, State: $state");

      if (state == BatteryState.discharging && level <= thresholdLevel) {
        final db = DB();
        final contacts = await db.getContacts();
        
        if (contacts.isNotEmpty) {
          final recipients = contacts.map((c) => c.number).toList();
          final message = "Emergency: My phone battery is critically low ($level%). "
              "I may not be able to respond soon. Please check on me if you don't hear from me.";
          
          try {
            // Initialize notifications
            final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();
            const AndroidInitializationSettings initializationSettingsAndroid =
                AndroidInitializationSettings('@mipmap/ic_launcher');
            const InitializationSettings initializationSettings =
                InitializationSettings(android: initializationSettingsAndroid);
            await notifications.initialize(initializationSettings);

            // Send SMS
            await sendSMS(
              message: message,
              recipients: recipients,
              sendDirect: true,
            );

            // Show notification
            const AndroidNotificationDetails androidPlatformChannelSpecifics =
                AndroidNotificationDetails(
              'battery_channel',
              'Battery Alerts',
              importance: Importance.high,
              priority: Priority.high,
              showWhen: false,
            );
            
            await notifications.show(
              1,
              'Emergency Alert Sent',
              'Low battery notification sent to your contacts',
              const NotificationDetails(android: androidPlatformChannelSpecifics),
            );

            logger.i("Background alert sent successfully");
            
            // Mark as sent in shared preferences to prevent duplicate sends
            await prefs.setBool('alertSent', true);
            
            // Schedule reset of the alertSent flag after 1 hour
            final now = DateTime.now();
            await prefs.setInt('resetAlertTime', now.add(const Duration(hours: 1)).millisecondsSinceEpoch);
            
          } catch (e) {
            logger.e("Failed to send SMS in background", error: e);
          }
        }
      }
      
      // Check if we need to reset the alert sent flag
      final resetTime = prefs.getInt('resetAlertTime') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (resetTime > 0 && now > resetTime) {
        await prefs.setBool('alertSent', false);
        await prefs.setInt('resetAlertTime', 0);
        logger.i("Reset alert sent flag");
      }
      
    } catch (e) {
      logger.e("Error in background task", error: e);
    } finally {
      // Release wake lock
      await WakelockPlus.disable();
    }
  }

  @override
  Widget build(BuildContext context) {
    Color batteryColor;
    if (_batteryLevel <= 20) {
      batteryColor = Colors.red;
    } else if (_batteryLevel <= 50) {
      batteryColor = Colors.orange;
    } else {
      batteryColor = Colors.green;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Battery Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettingsDialog(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBatteryStatusCard(batteryColor),
            const SizedBox(height: 20),
            _buildEmergencyContactsList(),
          ],
        ),
      ),
    );
  }

  // Settings dialog for configurability
  Future<void> _showSettingsDialog() async {
    int tempThreshold = _thresholdLevel;
    bool tempAutoSend = _autoSendEnabled;
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Battery Monitor Settings'),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Auto-send Messages'),
                  subtitle: const Text('Automatically send SMS when battery is low'),
                  value: tempAutoSend,
                  onChanged: (value) {
                    setState(() {
                      tempAutoSend = value;
                    });
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('Battery Threshold: '),
                    Expanded(
                      child: Slider(
                        value: tempThreshold.toDouble(),
                        min: 5,
                        max: 75,
                        divisions: 14,
                        label: '$tempThreshold%',
                        onChanged: (value) {
                          setState(() {
                            tempThreshold = value.round();
                          });
                        },
                      ),
                    ),
                    Text('$tempThreshold%'),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: const Text('Save'),
            onPressed: () {
              _safeSetState(() {
                _thresholdLevel = tempThreshold;
                _autoSendEnabled = tempAutoSend;
              });
              _saveSettings();
              
              // Restart the auto-send timer with new settings
              if (_autoSendEnabled) {
                _startAutoSendTimer();
              } else {
                _autoSendTimer?.cancel();
              }
              
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryStatusCard(Color batteryColor) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Battery Status',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: _batteryLevel / 100,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(batteryColor),
            ),
            const SizedBox(height: 10),
            Text(
              '$_batteryLevel%',
              style: TextStyle(
                fontSize: 24,
                color: batteryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _alertSent 
                ? 'Low battery alert has been sent to your emergency contacts'
                : _autoSendEnabled
                  ? 'Auto-send enabled. Alert will be sent when battery drops below $_thresholdLevel%'
                  : 'Auto-send disabled. Enable in settings to send alerts automatically',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                await _sendLowBatteryAlert();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Send Test Alert'),
            ),
            const SizedBox(height: 10),
            Text(
              'Background monitoring is ${_isMonitoring ? 'active' : 'inactive'} (${_autoSendEnabled ? 'Auto-send ON' : 'Auto-send OFF'})',
              style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyContactsList() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Emergency Contacts',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          _emergencyContacts.isEmpty
              ? const Expanded(
                  child: Center(
                    child: Text('No emergency contacts added yet'),
                  ),
                )
              : Expanded(
                  child: ListView.builder(
                    itemCount: _emergencyContacts.length,
                    itemBuilder: (context, index) {
                      final contact = _emergencyContacts[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          title: Text(contact.name),
                          subtitle: Text(contact.number),
                        ),
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }
}
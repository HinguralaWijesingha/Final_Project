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

// Keys for shared preferences
const String KEY_THRESHOLD_LEVEL = 'thresholdLevel';
const String KEY_AUTO_SEND_ENABLED = 'autoSendEnabled';
const String KEY_ALERT_SENT = 'alertSent';
const String KEY_ALERT_SENT_TIME = 'alertSentTime';
const String KEY_LAST_CHECK_TIME = 'lastCheckTime';

// Background task ID
const int BACKGROUND_TASK_ID = 0;

class BatteryMonitorPage extends StatefulWidget {
  const BatteryMonitorPage({super.key});

  @override
  State<BatteryMonitorPage> createState() => _BatteryMonitorPageState();
}

class _BatteryMonitorPageState extends State<BatteryMonitorPage> with WidgetsBindingObserver {
  final Battery _battery = Battery();
  int _batteryLevel = 100;
  bool _alertSent = false;
  List<Dcontacts> _emergencyContacts = [];
  final DB _db = DB();
  bool _isDisposed = false;
  StreamSubscription<BatteryState>? _batteryStateSubscription;
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final Logger _logger = Logger();
  
  // Settings variables
  int _thresholdLevel = 50; // Default threshold
  bool _autoSendEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initNotifications();
    _requestPermissions().then((_) {
      _loadEmergencyContacts();
      _loadSettings();
      _initBatteryMonitoring();
      _initBackgroundTask();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      // App is going to background
      _logger.i("App going to background - ensuring background task is running");
      _initBackgroundTask();
    } else if (state == AppLifecycleState.resumed) {
      // App is coming to foreground
      _logger.i("App resumed - checking battery level and refreshing UI");
      _checkBatteryLevel();
      _loadEmergencyContacts();
      _loadSettings();
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _safeSetState(() {
        _thresholdLevel = prefs.getInt(KEY_THRESHOLD_LEVEL) ?? 50;
        _autoSendEnabled = prefs.getBool(KEY_AUTO_SEND_ENABLED) ?? true;
        _alertSent = prefs.getBool(KEY_ALERT_SENT) ?? false;
      });
      
      // Check if we need to reset the alert sent flag after 1 hour
      final alertSentTime = prefs.getInt(KEY_ALERT_SENT_TIME) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (alertSentTime > 0 && now > alertSentTime + const Duration(hours: 1).inMilliseconds) {
        _safeSetState(() {
          _alertSent = false;
        });
        await prefs.setBool(KEY_ALERT_SENT, false);
        await prefs.setInt(KEY_ALERT_SENT_TIME, 0);
        _logger.i("Reset alert sent flag on app start");
      }
    } catch (e) {
      _logger.e("Failed to load settings", error: e);
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(KEY_THRESHOLD_LEVEL, _thresholdLevel);
      await prefs.setBool(KEY_AUTO_SEND_ENABLED, _autoSendEnabled);
      _logger.i("Settings saved: threshold=$_thresholdLevel%, autoSend=$_autoSendEnabled");
    } catch (e) {
      _logger.e("Failed to save settings", error: e);
    }
  }

  Future<void> _initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    
    await _notifications.initialize(initializationSettings);
    _logger.i("Notifications initialized");
  }

  Future<void> _requestPermissions() async {
    _logger.i("Requesting necessary permissions");
    
    // Request SMS permission
    if (!await Permission.sms.status.isGranted) {
      _logger.i("Requesting SMS permission");
      final status = await Permission.sms.request();
      _logger.i("SMS permission status: $status");
    }

    // Request notification permission
    if (!await Permission.notification.status.isGranted) {
      _logger.i("Requesting notification permission");
      final status = await Permission.notification.request();
      _logger.i("Notification permission status: $status");
    }

    // Request to ignore battery optimizations - this is critical for background operation
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      _logger.i("Requesting battery optimization permission");
      final status = await Permission.ignoreBatteryOptimizations.request();
      _logger.i("Battery optimization permission status: $status");
      
      if (await Permission.ignoreBatteryOptimizations.isPermanentlyDenied) {
        _logger.w("Battery optimization permission permanently denied, opening settings");
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
    _logger.i("Notification shown: $title - $body");
  }

  @override
  void dispose() {
    _isDisposed = true;
    _batteryStateSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadEmergencyContacts() async {
    try {
      List<Dcontacts> contacts = await _db.getContacts();
      _logger.i("Loaded ${contacts.length} emergency contacts");
      
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
      final level = await _battery.batteryLevel;
      _safeSetState(() {
        _batteryLevel = level;
      });
      _logger.i("Initial battery level: $_batteryLevel%");
      
      _batteryStateSubscription = _battery.onBatteryStateChanged.listen((BatteryState state) async {
        final currentLevel = await _battery.batteryLevel;
        _logger.i("Battery state changed: $state, level: $currentLevel%");
        
        _safeSetState(() {
          _batteryLevel = currentLevel;
        });
        
        // Check battery on every state change while app is open
        _checkBatteryLevel();
      });
    } catch (e) {
      _logger.e("Battery monitoring initialization failed", error: e);
    }
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) {
      setState(fn);
    }
  }

  Future<void> _checkBatteryLevel() async {
    _logger.i("Checking battery level");
    
    final prefs = await SharedPreferences.getInstance();
    final alertSent = prefs.getBool(KEY_ALERT_SENT) ?? false;
    
    _safeSetState(() {
      _alertSent = alertSent;
    });
    
    final currentLevel = await _battery.batteryLevel;
    _logger.i("Current battery level: $currentLevel%, threshold: $_thresholdLevel%, alertSent: $alertSent");
    
    _safeSetState(() {
      _batteryLevel = currentLevel;
    });
    
    if (_autoSendEnabled && 
        currentLevel <= _thresholdLevel && 
        !alertSent && 
        _emergencyContacts.isNotEmpty) {
      _logger.i("Battery level below threshold and alert not sent - sending alert");
      
      // Immediately set alert sent flag before attempting to send
      await prefs.setBool(KEY_ALERT_SENT, true);
      await prefs.setInt(KEY_ALERT_SENT_TIME, DateTime.now().millisecondsSinceEpoch);
      _safeSetState(() {
        _alertSent = true;
      });
      
      await _sendLowBatteryAlert();
    }
  }

  Future<void> _sendLowBatteryAlert() async {
    try {
      _logger.i("Preparing to send low battery alert");
      
      String message = "Emergency: My phone battery is critically low ($_batteryLevel%). "
          "I may not be able to respond soon. Please check on me if you don't hear from me.";

      List<String> recipients = _emergencyContacts.map((contact) => contact.number).toList();
      _logger.i("Sending alert to ${recipients.length} recipients: $recipients");

      await sendSMS(
        message: message,
        recipients: recipients,
        sendDirect: true,
      );

      _logger.i("SMS sent successfully");
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Low battery alert sent to emergency contacts')),
        );
      }
      
      await _showNotification('Emergency Alert Sent', 'Low battery notification sent to your contacts');
      
    } catch (e) {
      // If sending failed, reset the alert sent flag
      _logger.e('Failed to send low battery alert', error: e);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(KEY_ALERT_SENT, false);
      await prefs.setInt(KEY_ALERT_SENT_TIME, 0);
      
      _safeSetState(() {
        _alertSent = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send alert: ${e.toString()}')),
        );
      }
      await _showNotification('Alert Failed', 'Failed to send low battery alert');
    }
  }

  Future<void> _resetAlertStatus() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(KEY_ALERT_SENT, false);
    await prefs.setInt(KEY_ALERT_SENT_TIME, 0);
    
    _safeSetState(() {
      _alertSent = false;
    });
    
    _logger.i("Alert status reset");
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alert status reset - can send new alerts')),
      );
    }
  }

  Future<void> _initBackgroundTask() async {
    try {
      _logger.i("Initializing background task");
      await AndroidAlarmManager.initialize();
      
      // Cancel any existing alarm before setting a new one
      await AndroidAlarmManager.cancel(BACKGROUND_TASK_ID);
      
      // Set periodic task - run every 15 minutes for more frequent checking
      await AndroidAlarmManager.periodic(
        const Duration(minutes: 15), 
        BACKGROUND_TASK_ID,
        _checkBatteryInBackground,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
        allowWhileIdle: true,
      );
      
      // Also set a one-time task to run soon after app closes
      await AndroidAlarmManager.oneShot(
        const Duration(minutes: 1),
        BACKGROUND_TASK_ID + 1,  // Use a different ID
        _checkBatteryInBackground,
        exact: true,
        wakeup: true,
        allowWhileIdle: true,
      );
      
      _logger.i("Background tasks scheduled successfully");
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
    logger.i("Background task started");
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final thresholdLevel = prefs.getInt(KEY_THRESHOLD_LEVEL) ?? 50;
      final autoSendEnabled = prefs.getBool(KEY_AUTO_SEND_ENABLED) ?? true;
      final alertSent = prefs.getBool(KEY_ALERT_SENT) ?? false;
      
      logger.i("Background check - Settings loaded: threshold=$thresholdLevel%, autoSend=$autoSendEnabled, alertSent=$alertSent");
      
      // Skip if alert was already sent
      if (alertSent) {
        logger.i("Alert already sent. Skipping background check.");
        return;
      }
      
      // Skip if auto-send is disabled
      if (!autoSendEnabled) {
        logger.i("Auto-send is disabled. Skipping background check.");
        return;
      }
      
      // Add cooldown check (3 minutes minimum between checks)
      final lastCheckTime = prefs.getInt(KEY_LAST_CHECK_TIME) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastCheckTime < const Duration(minutes: 3).inMilliseconds) {
        logger.i("Skipping check - too soon since last check (${(now - lastCheckTime) ~/ 1000}s ago)");
        return;
      }
      await prefs.setInt(KEY_LAST_CHECK_TIME, now);
      
      // Ensure device stays awake during this process
      await WakelockPlus.enable();
      
      final battery = Battery();
      final level = await battery.batteryLevel;
      final state = await battery.batteryState;

      logger.i("Background check - Battery level: $level%, State: $state, Threshold: $thresholdLevel%");

      // Only check on discharging batteries to be safe
      if (level <= thresholdLevel) {
        logger.i("Battery level below threshold! Preparing to send alert");
        
        // Immediately set alert sent flag before attempting to send
        await prefs.setBool(KEY_ALERT_SENT, true);
        await prefs.setInt(KEY_ALERT_SENT_TIME, now);
        
        final db = DB();
        final contacts = await db.getContacts();
        logger.i("Loaded ${contacts.length} emergency contacts");
        
        if (contacts.isNotEmpty) {
          final recipients = contacts.map((c) => c.number).toList();
          final message = "Emergency: My phone battery is critically low ($level%). "
              "I may not be able to respond soon. Please check on me if you don't hear from me.";
          
          logger.i("Sending SMS to ${recipients.length} recipients");
          
          try {
            final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();
            const AndroidInitializationSettings initializationSettingsAndroid =
                AndroidInitializationSettings('@mipmap/ic_launcher');
            const InitializationSettings initializationSettings =
                InitializationSettings(android: initializationSettingsAndroid);
            await notifications.initialize(initializationSettings);

            await sendSMS(
              message: message,
              recipients: recipients,
              sendDirect: true,
            );

            logger.i("SMS sent successfully");

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
          } catch (e) {
            // If sending failed, reset the alert sent flag
            await prefs.setBool(KEY_ALERT_SENT, false);
            await prefs.setInt(KEY_ALERT_SENT_TIME, 0);
            logger.e("Failed to send SMS in background", error: e);
            
            // Try to show error notification
            try {
              final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();
              const AndroidInitializationSettings initializationSettingsAndroid =
                  AndroidInitializationSettings('@mipmap/ic_launcher');
              const InitializationSettings initializationSettings =
                  InitializationSettings(android: initializationSettingsAndroid);
              await notifications.initialize(initializationSettings);
              
              const AndroidNotificationDetails androidPlatformChannelSpecifics =
                  AndroidNotificationDetails(
                'battery_channel',
                'Battery Alerts',
                importance: Importance.high,
                priority: Priority.high,
                showWhen: false,
              );
              
              await notifications.show(
                2,
                'Alert Failed',
                'Failed to send low battery alert',
                const NotificationDetails(android: androidPlatformChannelSpecifics),
              );
            } catch (notificationError) {
              logger.e("Failed to show error notification", error: notificationError);
            }
          }
        } else {
          logger.w("No emergency contacts found - cannot send alert");
          // Reset alert sent flag since we didn't actually send anything
          await prefs.setBool(KEY_ALERT_SENT, false);
          await prefs.setInt(KEY_ALERT_SENT_TIME, 0);
        }
      }
    } catch (e) {
      logger.e("Error in background task", error: e);
    } finally {
      await WakelockPlus.disable();
      logger.i("Background task completed");
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
            onPressed: () async {
              _safeSetState(() {
                _thresholdLevel = tempThreshold;
                _autoSendEnabled = tempAutoSend;
              });
              await _saveSettings();
              await _checkBatteryLevel();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryStatusCard(Color batteryColor) {
    return Card(
      elevation: 4,
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
              minHeight: 12,
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
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      await _checkBatteryLevel();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Check Battery'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _alertSent
                      ? _resetAlertStatus
                      : _sendLowBatteryAlert,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _alertSent ? Colors.blue : Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(_alertSent ? 'Reset Alert' : 'Send Test Alert'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Background monitoring is active (${_autoSendEnabled ? 'Auto-send ON' : 'Auto-send OFF'})',
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Emergency Contacts',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              _emergencyContacts.isEmpty
                ? ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add Contacts'),
                    onPressed: () {
                      // Navigate to contact add page or show dialog
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please add contacts in the Contacts tab')),
                      );
                    },
                  )
                : IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _loadEmergencyContacts,
                    tooltip: 'Refresh contacts',
                  ),
            ],
          ),
          const SizedBox(height: 10),
          _emergencyContacts.isEmpty
              ? const Expanded(
                  child: Center(
                    child: Text(
                      'No emergency contacts added yet. Add contacts for battery alerts to work.',
                      textAlign: TextAlign.center,
                    ),
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
                          leading: CircleAvatar(
                            child: Text(contact.name[0].toUpperCase()),
                          ),
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
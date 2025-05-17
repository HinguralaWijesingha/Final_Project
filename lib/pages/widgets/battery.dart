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

// Create a global logger for background tasks
final Logger _globalLogger = Logger();

// Create a global function to send SMS that can be used in background
@pragma('vm:entry-point')
Future<void> sendSmsBackground(List<String> recipients, String message) async {
  try {
    await sendSMS(
      message: message,
      recipients: recipients,
      sendDirect: true,
    );
    _globalLogger.i("SMS sent successfully in background");
  } catch (e) {
    _globalLogger.e("Failed to send SMS in background", error: e);
  }
}

class _AppLifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onResumed;

  _AppLifecycleObserver({required this.onResumed});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResumed();
    }
  }
}

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
    _initSystem();
    
    // Register broadcast receiver for device screen state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerAppLifecycleEvents();
    });
  }
  
  void _registerAppLifecycleEvents() {
    WidgetsBinding.instance.addObserver(
      _AppLifecycleObserver(
        onResumed: () async {
          _logger.i("App resumed - checking battery");
          final level = await _battery.batteryLevel;
          _safeSetState(() {
            _batteryLevel = level;
          });
          _checkBatteryLevel(level);
          
          await _checkAlertSentStatus();
          _initBackgroundTask();
        },
      ),
    );
  }

  Future<void> _initSystem() async {
    try {
      await _initNotifications();
      await _requestPermissions();
      await _loadEmergencyContacts();
      await _loadSettings();
      await _checkAlertSentStatus();
      await _initBatteryMonitoring();
      await _initBackgroundTask();
      _startAutoSendTimer();
    } catch (e) {
      _logger.e("Initialization error", error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Initialization error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _checkAlertSentStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _safeSetState(() {
        _alertSent = prefs.getBool('alertSent') ?? false;
      });
      
      final resetTime = prefs.getInt('resetAlertTime') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (resetTime > 0 && now > resetTime) {
        _safeSetState(() {
          _alertSent = false;
        });
        await prefs.setBool('alertSent', false);
        await prefs.setInt('resetAlertTime', 0);
      }
    } catch (e) {
      _logger.e("Failed to check alert sent status", error: e);
    }
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
    _autoSendTimer?.cancel();
    
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
    Map<Permission, PermissionStatus> statuses = await [
      Permission.sms,
      Permission.notification,
    ].request();
    
    _logger.i("SMS permission status: ${statuses[Permission.sms]}");
    _logger.i("Notification permission status: ${statuses[Permission.notification]}");

    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      final status = await Permission.ignoreBatteryOptimizations.request();
      _logger.i("Battery optimization permission status: $status");
      
      if (await Permission.ignoreBatteryOptimizations.isPermanentlyDenied) {
        _logger.w("Battery optimization permission permanently denied");
        if (mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Permission Required'),
              content: const Text('This app needs to ignore battery optimizations to send alerts reliably. Please grant this permission in settings.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await openAppSettings();
                  },
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
        }
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
    super.dispose();
  }

  Future<void> _loadEmergencyContacts() async {
    try {
      List<Dcontacts> contacts = await _db.getContacts();
      _safeSetState(() {
        _emergencyContacts = contacts;
      });
      _logger.i("Loaded ${contacts.length} emergency contacts");
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
      int level = await _battery.batteryLevel;
      _safeSetState(() {
        _batteryLevel = level;
      });
      _logger.i("Initial battery level: $level%");
      
      _batteryStateSubscription = _battery.onBatteryStateChanged.listen((BatteryState state) async {
        final currentLevel = await _battery.batteryLevel;
        _safeSetState(() {
          _batteryLevel = currentLevel;
        });
        
        _logger.i("Battery state changed: $state, Level: $currentLevel%");
        
        if (state == BatteryState.discharging) {
          _startBatteryMonitoring();
        } else if (state == BatteryState.charging) {
          _safeSetState(() {
            _alertSent = false;
          });
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('alertSent', false);
        }
        
        _checkBatteryLevel(currentLevel);
      });

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
    _logger.i("Checking battery level: $level%, Threshold: $_thresholdLevel%, AlertSent: $_alertSent, AutoSend: $_autoSendEnabled");
    
    if (_autoSendEnabled && level <= _thresholdLevel && !_alertSent && _emergencyContacts.isNotEmpty) {
      _logger.i("Conditions met for sending alert");
      await _sendLowBatteryAlert();
      
      _safeSetState(() {
        _alertSent = true;
      });
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('alertSent', true);
      
      final now = DateTime.now();
      final resetTime = now.add(const Duration(hours: 1)).millisecondsSinceEpoch;
      await prefs.setInt('resetAlertTime', resetTime);
      
      _logger.i("Alert sent, reset scheduled for 1 hour later");
    }
  }

  Future<void> _sendLowBatteryAlert() async {
    try {
      if (await Permission.sms.status.isGranted == false) {
        _logger.e("SMS permission not granted");
        await _showNotification('Permission Error', 'SMS permission not granted. Cannot send alerts.');
        return;
      }

      if (_emergencyContacts.isEmpty) {
        _logger.e("No emergency contacts available");
        await _showNotification('Alert Failed', 'No emergency contacts available');
        return;
      }

      String message = "Emergency: My phone battery is critically low ($_batteryLevel%). "
          "I may not be able to respond soon. Please check on me if you don't hear from me.";

      List<String> recipients = _emergencyContacts.map((contact) => contact.number).toList();

      _logger.i("Attempting to send SMS to ${recipients.length} contacts");
      
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
      _logger.i('Low battery alert sent to contacts successfully');
    } catch (e) {
      _logger.e('Failed to send low battery alert', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send alert: ${e.toString()}')),
        );
      }
      await _showNotification('Alert Failed', 'Failed to send low battery alert');
    }
  }

  Future<void> _initBackgroundTask() async {
    try {
      final initialized = await AndroidAlarmManager.initialize();
      _logger.i("AndroidAlarmManager initialized: $initialized");
      
      await AndroidAlarmManager.cancel(0);
      
      final scheduled = await AndroidAlarmManager.periodic(
        const Duration(minutes: 15),
        0,
        _checkBatteryInBackground,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
        allowWhileIdle: true,
      );
      
      await AndroidAlarmManager.oneShotAt(
        DateTime.now().add(const Duration(minutes: 1)),
        1,
        _checkBatteryInBackground,
        exact: true,
        wakeup: true,
        allowWhileIdle: true,
      );
      
      _logger.i("Background task scheduled: $scheduled");
      
      if (mounted) {
        _showBatteryOptimizationDialog();
      }
      
      if (!scheduled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to schedule background task')),
          );
        }
      }
    } catch (e) {
      _logger.e("Failed to initialize background task", error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to setup background monitoring: ${e.toString()}')),
        );
      }
    }
  }
  
  Future<void> _showBatteryOptimizationDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Important: Enable Full Background Access'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This app needs to run in the background to monitor your battery level and send emergency alerts when your battery is low.',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            Text(
              'Please ensure you:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('1. Disable battery optimization for this app'),
            Text('2. Allow app to run in background'),
            Text('3. Allow app to auto-start (on some devices)'),
            SizedBox(height: 16),
            Text(
              'Different phones have different settings. Look for:',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
            Text('• Battery > Battery optimization'),
            Text('• Security > App permissions'),
            Text('• Apps > Your app > Battery'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<void> _checkBatteryInBackground() async {
    final logger = Logger();
    
    const AndroidNotificationDetails foregroundServiceChannel = AndroidNotificationDetails(
      'foreground_service_channel',
      'Foreground Service',
      importance: Importance.low,
      priority: Priority.low,
      showWhen: false,
      ongoing: true,
    );
    
    try {
      logger.i("Background battery check started");
      
      final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);
      await notifications.initialize(initializationSettings);
      
      await notifications.show(
        999,
        'Battery Monitor Running',
        'Monitoring battery level in background',
        const NotificationDetails(android: foregroundServiceChannel),
      );
      
      final prefs = await SharedPreferences.getInstance();
      final thresholdLevel = prefs.getInt('thresholdLevel') ?? 50;
      final autoSendEnabled = prefs.getBool('autoSendEnabled') ?? true;
      final alertSent = prefs.getBool('alertSent') ?? false;
      
      logger.i("Settings loaded - threshold: $thresholdLevel%, autoSend: $autoSendEnabled, alertSent: $alertSent");
      
      if (!autoSendEnabled) {
        logger.i("Auto-send is disabled. Skipping background check.");
        return;
      }
      
      if (alertSent) {
        final resetTime = prefs.getInt('resetAlertTime') ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        
        logger.i("Alert already sent. Reset time: $resetTime, Now: $now");
        
        if (resetTime > 0 && now > resetTime) {
          await prefs.setBool('alertSent', false);
          await prefs.setInt('resetAlertTime', 0);
          logger.i("Reset alert sent flag");
        } else {
          logger.i("Alert was already sent and is still in cooldown period");
          return;
        }
      }
      
      await WakelockPlus.enable();
      
      final battery = Battery();
      final level = await battery.batteryLevel;
      final state = await battery.batteryState;

      logger.i("Background check - Battery level: $level%, State: $state");

      if (state == BatteryState.discharging && level <= thresholdLevel) {
        final db = DB();
        final contacts = await db.getContacts();
        
        logger.i("Loaded ${contacts.length} contacts for background alert");
        
        if (contacts.isNotEmpty) {
          final recipients = contacts.map((c) => c.number).toList();
          final message = "Emergency: My phone battery is critically low ($level%). "
              "I may not be able to respond soon. Please check on me if you don't hear from me.";
          
          try {
            final smsPermission = await Permission.sms.status;
            logger.i("SMS permission status: $smsPermission");
            
            if (smsPermission.isGranted) {
              await sendSMS(
                message: message,
                recipients: recipients,
                sendDirect: true,
              );

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
              
              await prefs.setBool('alertSent', true);
              
              final now = DateTime.now();
              await prefs.setInt('resetAlertTime', now.add(const Duration(hours: 1)).millisecondsSinceEpoch);
              
              await AndroidAlarmManager.oneShotAt(
                DateTime.now().add(const Duration(minutes: 30)),
                2,
                _checkBatteryInBackground,
                exact: true,
                wakeup: true,
                allowWhileIdle: true,
              );
            } else {
              logger.e("SMS permission not granted for background alert");
              
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
                'SMS permission not granted. Cannot send low battery alert.',
                const NotificationDetails(android: androidPlatformChannelSpecifics),
              );
            }
          } catch (e) {
            logger.e("Failed to send SMS in background", error: e);
            
            try {
              const AndroidNotificationDetails androidPlatformChannelSpecifics =
                  AndroidNotificationDetails(
                'battery_channel',
                'Battery Alerts',
                importance: Importance.high,
                priority: Priority.high,
                showWhen: false,
              );
              
              await notifications.show(
                3,
                'Alert Failed',
                'Error sending low battery alert: ${e.toString()}',
                const NotificationDetails(android: androidPlatformChannelSpecifics),
              );
            } catch (notificationError) {
              logger.e("Failed to show error notification", error: notificationError);
            }
          }
        } else {
          logger.w("No contacts available for background alert");
        }
      } else {
        if (level <= thresholdLevel + 10 && level > thresholdLevel) {
          logger.i("Battery getting close to threshold. Scheduling follow-up check.");
          await AndroidAlarmManager.oneShotAt(
            DateTime.now().add(const Duration(minutes: 5)),
            3,
            _checkBatteryInBackground,
            exact: true,
            wakeup: true,
            allowWhileIdle: true,
          );
        }
      }
    } catch (e) {
      logger.e("Error in background task", error: e);
    } finally {
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
        //title: const Text('Battery Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettingsDialog(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              final level = await _battery.batteryLevel;
              _safeSetState(() {
                _batteryLevel = level;
              });
              _checkBatteryLevel(level);
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Battery level refreshed')),
                );
              }
            },
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
                _alertSent = false;
              });
              await _saveSettings();
              
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('alertSent', false);
              await prefs.setInt('resetAlertTime', 0);
              
              if (_autoSendEnabled) {
                _startAutoSendTimer();
              } else {
                _autoSendTimer?.cancel();
              }
              
              Navigator.of(context).pop();
              
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Settings saved')),
              );
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
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _batteryLevel / 100,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(batteryColor),
              minHeight: 10,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$_batteryLevel%',
                  style: TextStyle(
                    fontSize: 36,
                    color: batteryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Icon(
                  Icons.battery_alert,
                  color: batteryColor,
                  size: 36,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _alertSent 
                ? 'Low battery alert has been sent to your emergency contacts'
                : _autoSendEnabled
                  ? 'Auto-send enabled. Alert will be sent when battery drops below $_thresholdLevel%'
                  : 'Auto-send disabled. Enable in settings to send alerts automatically',
              style: TextStyle(
                fontSize: 14,
                fontWeight: _alertSent ? FontWeight.bold : FontWeight.normal,
                color: _alertSent ? Colors.red : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      await _sendLowBatteryAlert();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Send Test Alert'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      _safeSetState(() {
                        _alertSent = false;
                      });
                      
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('alertSent', false);
                      await prefs.setInt('resetAlertTime', 0);
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Alert status reset')),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Reset Status'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _isMonitoring ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _isMonitoring ? Icons.check_circle : Icons.info,
                    color: _isMonitoring ? Colors.green : Colors.orange,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Background monitoring is ${_isMonitoring ? 'active' : 'inactive'} (${_autoSendEnabled ? 'Auto-send ON' : 'Auto-send OFF'})',
                      style: TextStyle(
                        fontSize: 12, 
                        fontStyle: FontStyle.italic,
                        color: _isMonitoring ? Colors.green : Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
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
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Emergency Contacts',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              
            ],
          ),
          const SizedBox(height: 10),
          _emergencyContacts.isEmpty
              ? const Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.contact_phone, size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No emergency contacts added yet',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _emergencyContacts.length,
                  itemBuilder: (context, index) {
                    final contact = _emergencyContacts[index];
                    return ListTile(
                      leading: const Icon(Icons.contact_emergency),
                      title: Text(contact.name),
                      subtitle: Text(contact.number),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () async {
                          await _db.deleteContact(contact.id);
                          await _loadEmergencyContacts();
                        },
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}
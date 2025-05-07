import 'dart:async';
import 'package:flutter/material.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:safe_pulse/db/db.dart';
import 'package:safe_pulse/model/contactdb.dart';
import 'package:workmanager/workmanager.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';

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

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _requestPermissions().then((_) {
      _loadEmergencyContacts();
      _initBatteryMonitoring();
      _initBackgroundTask();
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
    await Permission.sms.request();
    await Permission.notification.request();
    await Permission.ignoreBatteryOptimizations.request();
  }

  Future<void> _showNotification(String title, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'battery_channel',
      'Battery Alerts',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: false,
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
    Workmanager().cancelByTag("batteryCheckTask");
    AndroidAlarmManager.cancel(0);
    super.dispose();
  }

  Future<void> _loadEmergencyContacts() async {
    List<Dcontacts> contacts = await _db.getContacts();
    if (!mounted) return;
    setState(() {
      _emergencyContacts = contacts;
    });
  }

  Future<void> _initBatteryMonitoring() async {
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

    _startPeriodicBatteryCheck();
  }

  void _startPeriodicBatteryCheck() {
    if (_isDisposed) return;
    
    Future.delayed(const Duration(minutes: 1), () {
      if (_isDisposed) return;
      
      _battery.batteryLevel.then((level) {
        _safeSetState(() {
          _batteryLevel = level;
        });
        _checkBatteryLevel(level);
      });
      
      if (_isMonitoring) {
        _startPeriodicBatteryCheck();
      }
    });
  }

  void _startBatteryMonitoring() {
    _safeSetState(() {
      _isMonitoring = true;
    });
    _checkBatteryLevel(_batteryLevel);
    _startPeriodicBatteryCheck();
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) {
      setState(fn);
    }
  }

  Future<void> _checkBatteryLevel(int level) async {
    if (level <= 50 && !_alertSent && _isMonitoring && _emergencyContacts.isNotEmpty) {
      await _sendLowBatteryAlert();
      _safeSetState(() {
        _alertSent = true;
      });
    }
  }

  Future<void> _sendLowBatteryAlert() async {
    try {
      String message = "Emergency: My phone battery is critically low ($_batteryLevel%). "
          "I may not be able to respond soon. Please check on me if you don't hear from me.";

      List<String> recipients = _emergencyContacts.map((contact) => contact.number).toList();

      // Send SMS without capturing unused result
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
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );

    await Workmanager().registerPeriodicTask(
      "batteryCheckTask",
      "batteryCheckTask",
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
        requiresStorageNotLow: false,
      ),
      initialDelay: const Duration(seconds: 10),
    );

    await AndroidAlarmManager.initialize();
    await AndroidAlarmManager.periodic(
      const Duration(minutes: 15),
      0,
      _checkBatteryInBackground,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
    );
  }

  @pragma('vm:entry-point')
  static Future<void> _checkBatteryInBackground() async {
    final logger = Logger();
    final battery = Battery();
    final level = await battery.batteryLevel;
    final state = await battery.batteryState;

    if (state == BatteryState.discharging && level <= 50) {
      final db = DB();
      final contacts = await db.getContacts();
      if (contacts.isNotEmpty) {
        final recipients = contacts.map((c) => c.number).toList();
        final message = "Emergency: My phone battery is critically low ($level%). "
            "I may not be able to respond soon. Please check on me if you don't hear from me.";
        
        try {
          // Initialize notifications in background
          final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();
          const AndroidInitializationSettings initializationSettingsAndroid =
              AndroidInitializationSettings('@mipmap/ic_launcher');
          const InitializationSettings initializationSettings =
              InitializationSettings(android: initializationSettingsAndroid);
          await notifications.initialize(initializationSettings);

          // Send SMS without capturing unused result
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
          const NotificationDetails platformChannelSpecifics =
              NotificationDetails(android: androidPlatformChannelSpecifics);
          
          await notifications.show(
            1,
            'Emergency Alert Sent',
            'Low battery notification sent to your contacts',
            platformChannelSpecifics,
          );

          logger.i("Background alert sent successfully");
        } catch (e) {
          logger.e("Failed to send SMS in background", error: e);
        }
      }
    }
  }

  @pragma('vm:entry-point')
  static void callbackDispatcher() {
    Workmanager().executeTask((task, inputData) async {
      await _checkBatteryInBackground();
      return Future.value(true);
    });
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
            onPressed: () {
              openAppSettings();
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
                : _isMonitoring
                  ? 'Monitoring battery level. Alert will be sent if battery drops below 50%'
                  : 'Monitoring paused (device is charging)',
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
import 'package:flutter/material.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:safe_pulse/db/db.dart';
import 'package:safe_pulse/model/contactdb.dart';
import 'package:workmanager/workmanager.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

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

  @override
  void initState() {
    super.initState();
    _loadEmergencyContacts();
    _initBatteryMonitoring();
    _initBackgroundTask();
  }

  Future<void> _loadEmergencyContacts() async {
    List<Dcontacts> contacts = await _db.getContacts();
    setState(() {
      _emergencyContacts = contacts;
    });
  }

  Future<void> _initBatteryMonitoring() async {
    _batteryLevel = await _battery.batteryLevel;
    
    _battery.onBatteryStateChanged.listen((BatteryState state) async {
      if (state == BatteryState.discharging) {
        _startBatteryMonitoring();
      } else {
        setState(() {
          _alertSent = false;
        });
      }
      _checkBatteryLevel(await _battery.batteryLevel);
    });

    _startPeriodicBatteryCheck();
  }

  void _startPeriodicBatteryCheck() {
    Future.delayed(const Duration(seconds: 30), () {
      if (_isMonitoring) {
        _battery.batteryLevel.then((level) {
          setState(() {
            _batteryLevel = level;
          });
          _checkBatteryLevel(level);
        });
        _startPeriodicBatteryCheck();
      }
    });
  }

  void _startBatteryMonitoring() {
    if (!_isMonitoring) {
      setState(() {
        _isMonitoring = true;
      });
      _checkBatteryLevel(_batteryLevel);
      _startPeriodicBatteryCheck();
    }
  }

  Future<void> _checkBatteryLevel(int level) async {
    if (level <= 50 && !_alertSent && _isMonitoring && _emergencyContacts.isNotEmpty) {
      await _sendLowBatteryAlert();
      setState(() {
        _alertSent = true;
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send alert: ${e.toString()}')),
        );
      }
    }
  }

  // Background task initialization
  Future<void> _initBackgroundTask() async {
    // Initialize WorkManager
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );

    // Register periodic task (Android)
    await Workmanager().registerPeriodicTask(
      "batteryCheckTask",
      "batteryCheckTask",
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );

    // Initialize Android Alarm Manager
    await AndroidAlarmManager.initialize();
    await AndroidAlarmManager.periodic(
      const Duration(minutes: 15),
      0, // Unique ID
      _checkBatteryInBackground,
      exact: true,
      wakeup: true,
    );
  }

  // Background task function
  @pragma('vm:entry-point')
  static Future<void> _checkBatteryInBackground() async {
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
          await sendSMS(
            message: message,
            recipients: recipients,
            sendDirect: true,
          );
          print("Background alert sent successfully");
        } catch (e) {
          print("Failed to send SMS in background: $e");
        }
      }
    }
  }

  // Callback dispatcher for WorkManager
  @pragma('vm:entry-point')
  static void callbackDispatcher() {
    Workmanager().executeTask((task, inputData) async {
      await _checkBatteryInBackground();
      return true;
    });
  }

  @override
  void dispose() {
    Workmanager().cancelByTag("batteryCheckTask");
    AndroidAlarmManager.cancel(0);
    super.dispose();
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
                          trailing: const Icon(
                            Icons.emergency,
                            color: Colors.red,
                          ),
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
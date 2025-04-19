import 'package:flutter/material.dart';
import 'package:safe_pulse/pages/public_emergency/live_help.dart';
import 'package:safe_pulse/pages/public_emergency/public_emergency.dart';
import 'package:safe_pulse/db/db.dart';
import 'package:safe_pulse/model/contactdb.dart';
import 'package:url_launcher/url_launcher.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DB _db = DB();
  List<Dcontacts> emergencyContacts = [];
  bool isSendingAlerts = false;

  @override
  void initState() {
    super.initState();
    _loadEmergencyContacts();
  }

  Future<void> _loadEmergencyContacts() async {
    List<Dcontacts> contacts = await _db.getContacts();
    setState(() {
      emergencyContacts = contacts;
    });
  }

  Future<void> _sendEmergencyMessage() async {
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
    
    for (var contact in emergencyContacts) {
      try {
        final phoneNumber = contact.number.replaceAll(RegExp(r'[^0-9+]'), '');
        if (phoneNumber.isEmpty) {
          failedSends++;
          continue;
        }
        
        final smsUri = Uri.parse('sms:$phoneNumber?body=${Uri.encodeComponent(message)}');
        
        if (await canLaunchUrl(smsUri)) {
          await launchUrl(smsUri);
          successfulSends++;
        } else {
          debugPrint("Could not launch SMS for ${contact.name}");
          failedSends++;
        }
      } catch (e) {
        debugPrint("Error sending to ${contact.name}: $e");
        failedSends++;
      }
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
                child: ElevatedButton(
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
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            //padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Public Emergency Contacts",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 8),
                const PublicEmergencyContacts(),
                const SizedBox(height: 16),
                const Text(
                  "Live Help",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 8),
                const LiveHelp(),
                const SizedBox(height: 8),
                const Text(
                  "Emergency SOS",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
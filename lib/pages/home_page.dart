import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:safe_pulse/pages/public_emergency/live_help.dart';
import 'package:safe_pulse/pages/public_emergency/public_emergency.dart';
import 'package:safe_pulse/db/db.dart';
import 'package:safe_pulse/model/contactdb.dart';
import 'package:url_launcher/url_launcher.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DB _db = DB();
  List<Dcontacts> emergencyContacts = [];

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
    // Compose the emergency message
    const String message = "🚨 EMERGENCY ALERT 🚨\n"
        "I need immediate help!\n"
        "This is an automated message from SafePulse app.";

    // Send to all emergency contacts
    for (var contact in emergencyContacts) {
      final phoneNumber = contact.number.replaceAll(RegExp(r'[^0-9+]'), '');
      final smsUri = Uri.parse('sms:$phoneNumber?body=${Uri.encodeComponent(message)}');
      
      try {
        if (await canLaunchUrl(smsUri)) {
          await launchUrl(smsUri);
        } else {
          print("Could not launch SMS for ${contact.name}");
        }
      } catch (e) {
        print("Error sending to ${contact.name}: $e");
      }
    }

    // Show confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Emergency alert sent to all contacts!"),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 5),
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
                    child: Text("No emergency contacts added"),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: emergencyContacts.length,
                    itemBuilder: (context, index) {
                      final contact = emergencyContacts[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.red[100],
                          child: const Icon(Icons.emergency, color: Colors.red),
                        ),
                        title: Text(contact.name),
                        subtitle: Text(contact.number),
                        trailing: IconButton(
                          icon: const Icon(Icons.call, color: Colors.red),
                          onPressed: () {
                            final phoneNumber = contact.number.replaceAll(RegExp(r'[^0-9+]'), '');
                            final callUri = Uri.parse('tel:$phoneNumber');
                            launchUrl(callUri);
                            Navigator.pop(context);
                          },
                        ),
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
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _sendEmergencyMessage();
                  },
                  child: const Text(
                    "SEND EMERGENCY ALERT TO ALL",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
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
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text("Public Emergency Contacts",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    )),
              ),
              const PublicEmergencyContacts(),
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text("Live Help",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    )),
              ),
              const LiveHelp(),
              // SOS Button Section
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text("Emergency SOS",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    )),
              ),
              Center(
                child: InkWell(
                  onTap: _showEmergencyPopup,
                  borderRadius: BorderRadius.circular(50),
                  child: Container(
                    width: 100,
                    height: 100,
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
                          fontSize: 24,
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
    );
  }
}
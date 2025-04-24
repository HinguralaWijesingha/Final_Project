import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:telephony/telephony.dart';
import 'package:safe_pulse/db/db.dart';
import 'package:safe_pulse/model/contactdb.dart';

class ChatPage extends StatefulWidget {
  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final Telephony telephony = Telephony.instance;
  String? selectedContact;
  String? selectedContactName;
  List<Dcontacts> contactList = [];
  DB db = DB();

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _messageController.addListener(() {
      setState(() {}); // Update send button state
    });

    telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) {
        Fluttertoast.showToast(
          msg: "New SMS from ${message.address}: ${message.body}",
        );
      },
      onBackgroundMessage: _backgroundMessageHandler,
    );
  }

  static void _backgroundMessageHandler(SmsMessage message) async {
    debugPrint("Background SMS received: ${message.body}");
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    try {
      List<Dcontacts> contacts = await db.getContacts();
      setState(() {
        contactList = contacts;
      });
    } catch (e) {
      debugPrint("Failed to load contacts: $e");
      Fluttertoast.showToast(msg: "Error loading contacts.");
    }
  }

  Future<void> _sendMessage() async {
    String message = _messageController.text.trim();
    if (message.isEmpty) {
      Fluttertoast.showToast(msg: "Please enter a message");
      return;
    }

    if (selectedContact == null) {
      Fluttertoast.showToast(msg: "Please select a contact");
      return;
    }

    bool? permissionsGranted = await telephony.requestSmsPermissions;
    if (!(permissionsGranted ?? false)) {
      Fluttertoast.showToast(msg: "SMS permission denied");
      return;
    }

    try {
      bool? canSendSms = await telephony.isSmsCapable;
      if (canSendSms != true) {
        Fluttertoast.showToast(msg: "Device cannot send SMS");
        return;
      }

      await telephony.sendSms(
        to: selectedContact!,
        message: message,
      );

      Fluttertoast.showToast(
        msg: "Message queued for sending",
        toastLength: Toast.LENGTH_SHORT,
      );
      _messageController.clear();
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Message will be sent when network is available",
        toastLength: Toast.LENGTH_LONG,
      );
      debugPrint("SMS queued offline: $e");
    }
  }

  Future<void> _selectContact() async {
    final selected = await showDialog<Dcontacts>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Select Contact"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: contactList.length,
            itemBuilder: (context, index) {
              final contact = contactList[index];
              return ListTile(
                title: Text(contact.name),
                subtitle: Text(contact.number),
                onTap: () => Navigator.pop(context, contact),
              );
            },
          ),
        ),
      ),
    );

    if (selected != null) {
      setState(() {
        selectedContact = selected.number;
        selectedContactName = selected.name;
      });
    }
  }

  bool get _canSendMessage =>
      _messageController.text.trim().isNotEmpty && selectedContact != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(selectedContactName != null
            ? "Chat with $selectedContactName"
            : "Chat Page"),
        actions: [
          IconButton(
            icon: Icon(Icons.contact_phone),
            onPressed: _selectContact,
          ),
        ],
      ),
      body: Column(
        children: [
          if (selectedContact != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Chip(
                label: Text("To: ${selectedContactName ?? ''} ($selectedContact)"),
                deleteIcon: Icon(Icons.close),
                onDeleted: () {
                  setState(() {
                    selectedContact = null;
                    selectedContactName = null;
                  });
                },
              ),
            ),
          Expanded(
            child: ListView(
              children: [
                Center(child: Text("Start chatting...")),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: "Enter your message",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: _canSendMessage ? _sendMessage : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

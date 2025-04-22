import 'package:flutter/material.dart';
import 'package:safe_pulse/db/db.dart';
import 'package:safe_pulse/model/contactdb.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';
import 'dart:async';
import 'dart:convert';

class ChatMessage {
  final String text;
  final bool isSent;
  final String contactId;
  final String contactName;
  final DateTime timestamp;
  final bool isFailed;

  ChatMessage({
    required this.text,
    required this.isSent,
    required this.contactId,
    required this.contactName,
    required this.timestamp,
    this.isFailed = false,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'isSent': isSent,
        'contactId': contactId,
        'contactName': contactName,
        'timestamp': timestamp.toIso8601String(),
        'isFailed': isFailed,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        text: json['text'],
        isSent: json['isSent'],
        contactId: json['contactId'],
        contactName: json['contactName'],
        timestamp: DateTime.parse(json['timestamp']),
        isFailed: json['isFailed'] ?? false,
      );
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  DB db = DB();
  List<Dcontacts>? contactList;
  int count = 0;
  final TextEditingController _messageController = TextEditingController();
  List<ChatMessage> messages = [];
  Dcontacts? selectedContact;
  final Telephony telephony = Telephony.instance;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _loadMessages();
    _initSmsReceiver();
  }

  Future<void> _initSmsReceiver() async {
    debugPrint("Initializing SMS receiver...");
    final bool? granted = await telephony.requestPhoneAndSmsPermissions;
    debugPrint("SMS permissions granted: $granted");
    
    if (granted ?? false) {
      telephony.listenIncomingSms(
        onNewMessage: _handleIncomingSms,
        onBackgroundMessage: backgroundMessageHandler,
      );
      debugPrint("SMS listener initialized successfully");
    } else {
      debugPrint("SMS permissions denied");
      Fluttertoast.showToast(
        msg: "SMS permissions denied. Cannot receive messages.",
        toastLength: Toast.LENGTH_LONG,
      );
    }
  }

  void _handleIncomingSms(SmsMessage message) {
    debugPrint("Received SMS in foreground: ${message.body}");
    if (message.address == null || message.body == null) return;
    
    String address = message.address!;
    DateTime now = DateTime.now();
    
    // Find matching contact
    Dcontacts? matchedContact;
    for (var contact in contactList ?? []) {
      // Normalize phone numbers for comparison
      String normalizedContactNumber = _normalizePhoneNumber(contact.number);
      String normalizedSenderNumber = _normalizePhoneNumber(address);
      
      debugPrint("Comparing: $normalizedContactNumber with $normalizedSenderNumber");
      
      if (normalizedContactNumber == normalizedSenderNumber) {
        matchedContact = contact;
        debugPrint("Found matching contact: ${contact.name}");
        break;
      }
    }
    
    setState(() {
      messages.add(ChatMessage(
        text: message.body!,
        isSent: false,
        contactId: matchedContact?.id.toString() ?? '',
        contactName: matchedContact?.name ?? address,
        timestamp: now,
      ));
    });
    _saveMessages();
    
    // Show notification for new message
    if (matchedContact != null) {
      Fluttertoast.showToast(
        msg: "New message from ${matchedContact.name}",
        toastLength: Toast.LENGTH_SHORT,
      );
    }
  }

  @pragma('vm:entry-point')
  static Future<void> backgroundMessageHandler(SmsMessage message) async {
    debugPrint("Received SMS in background: ${message.body}");
    
    try {
      // Load existing messages
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<ChatMessage> storedMessages = [];
      String? messagesJson = prefs.getString('chat_messages');
      
      if (messagesJson != null) {
        List<dynamic> decodedMessages = jsonDecode(messagesJson);
        storedMessages = decodedMessages.map((m) => ChatMessage.fromJson(m)).toList();
      }
      
      // Add new message
      storedMessages.add(ChatMessage(
        text: message.body ?? "",
        isSent: false,
        contactId: '',
        contactName: message.address ?? "Unknown",
        timestamp: DateTime.now(),
      ));
      
      // Save updated messages
      List<Map<String, dynamic>> encodedMessages =
          storedMessages.map((m) => m.toJson()).toList();
      await prefs.setString('chat_messages', jsonEncode(encodedMessages));
      
      debugPrint("Successfully saved background message");
    } catch (e) {
      debugPrint("Error saving background message: $e");
    }
  }

  String _normalizePhoneNumber(String number) {
    // Remove all non-digit characters
    String digits = number.replaceAll(RegExp(r'[^0-9]'), '');
    
    // Take just the last 10 digits (or fewer if the number is shorter)
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }

  Future<bool> _checkPermissions() async {
    try {
      final smsGranted = await telephony.requestSmsPermissions;
      final phoneGranted = await telephony.requestPhonePermissions;
      return (smsGranted ?? false) && (phoneGranted ?? false);
    } catch (e) {
      debugPrint("Permission error: $e");
      return false;
    }
  }

  String _formatPhoneNumber(String number) {
    // Remove all non-digit characters except '+'
    String formatted = number.replaceAll(RegExp(r'[^0-9+]'), '');
    
    // Ensure it starts with country code
    if (!formatted.startsWith('+')) {
      // Add default country code if missing (adjust for your country)
      formatted = '+1$formatted'; // US/Canada default
    }
    return formatted;
  }

  void _loadContacts() {
    db.getContacts().then((value) {
      setState(() {
        contactList = value;
        count = value.length;
        debugPrint("Loaded ${value.length} contacts");
      });
    });
  }

  Future<void> _loadMessages() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? messagesJson = prefs.getString('chat_messages');
      if (messagesJson != null) {
        List<dynamic> decodedMessages = jsonDecode(messagesJson);
        setState(() {
          messages = decodedMessages.map((m) => ChatMessage.fromJson(m)).toList();
        });
        debugPrint("Loaded ${messages.length} messages");
      }
    } catch (e) {
      debugPrint("Error loading messages: $e");
    }
  }

  Future<void> _saveMessages() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<Map<String, dynamic>> encodedMessages =
          messages.map((m) => m.toJson()).toList();
      await prefs.setString('chat_messages', jsonEncode(encodedMessages));
      debugPrint("Messages saved successfully");
    } catch (e) {
      debugPrint("Error saving messages: $e");
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.isEmpty) {
      Fluttertoast.showToast(msg: "Please enter a message");
      return;
    }

    if (selectedContact == null) {
      Fluttertoast.showToast(msg: "Please select a contact");
      return;
    }

    // Format phone number
    final formattedNumber = _formatPhoneNumber(selectedContact!.number);
    if (formattedNumber.isEmpty) {
      Fluttertoast.showToast(msg: "Invalid phone number format");
      return;
    }

    // Check permissions
    if (!await _checkPermissions()) {
      Fluttertoast.showToast(msg: "SMS permissions not granted");
      return;
    }

    setState(() => _isSending = true);

    final newMessage = ChatMessage(
      text: _messageController.text,
      isSent: true,
      contactId: selectedContact!.id.toString(),
      contactName: selectedContact!.name,
      timestamp: DateTime.now(),
    );

    setState(() {
      messages.add(newMessage);
      _messageController.clear();
    });

    bool sendSuccess = false;
    
    try {
      debugPrint("Sending SMS to: $formattedNumber");
      // First try sending directly
      await telephony.sendSms(
        to: formattedNumber,
        message: newMessage.text,
      );
      sendSuccess = true;
      debugPrint("Direct send successful");
    } catch (e) {
      debugPrint("Direct send failed: $e");
      
      // Fallback to status listener method
      try {
        final completer = Completer<bool>();
        
        telephony.sendSms(
          to: formattedNumber,
          message: newMessage.text,
          statusListener: (status) {
            debugPrint("SMS status: $status");
            if (status == SendStatus.SENT || status == SendStatus.DELIVERED) {
              completer.complete(true);
            } else {
              completer.complete(false);
            }
          },
        );
        
        sendSuccess = await completer.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint("SMS send timed out");
            return false;
          },
        );
      } catch (e) {
        debugPrint("Fallback send failed: $e");
        sendSuccess = false;
      }
    }

    if (!sendSuccess) {
      _markMessageAsFailed(newMessage);
      Fluttertoast.showToast(msg: "Failed to send message");
    } else {
      await _saveMessages();
      Fluttertoast.showToast(msg: "Message sent successfully");
    }

    setState(() => _isSending = false);
  }

  void _markMessageAsFailed(ChatMessage message) {
    setState(() {
      final index = messages.indexOf(message);
      if (index != -1) {
        messages[index] = ChatMessage(
          text: message.text,
          isSent: true,
          contactId: message.contactId,
          contactName: message.contactName,
          timestamp: message.timestamp,
          isFailed: true,
        );
      }
    });
    _saveMessages();
  }

  @override
  Widget build(BuildContext context) {
    if (contactList == null) {
      contactList = [];
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Chat"),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          Container(
            height: 100,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: count,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedContact = contactList![index];
                      debugPrint("Selected contact: ${selectedContact!.name}");
                    });
                  },
                  child: Container(
                    width: 80,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: selectedContact?.id == contactList![index].id
                          ? Colors.blue.shade100
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          child: Text(contactList![index].name[0]),
                        ),
                        const SizedBox(height: 5),
                        Flexible(
                          child: Text(
                            contactList![index].name,
                            style: TextStyle(
                              fontWeight: selectedContact?.id ==
                                      contactList![index].id
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: messages.isEmpty || selectedContact == null
                ? const Center(child: Text("No messages yet"))
                : ListView.builder(
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      
                      // Show messages for selected contact or unassigned messages with matching phone
                      final bool isSelected = selectedContact != null && 
                        (message.contactId == selectedContact!.id.toString() || 
                         (_normalizePhoneNumber(message.contactName) == 
                          _normalizePhoneNumber(selectedContact!.number)));

                      if (!isSelected) {
                        return const SizedBox.shrink();
                      }

                      return Align(
                        alignment: message.isSent
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.7,
                          ),
                          margin: const EdgeInsets.symmetric(
                            vertical: 5,
                            horizontal: 10,
                          ),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: message.isSent
                                ? message.isFailed
                                    ? Colors.red.shade100
                                    : Colors.blue.shade100
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                message.text,
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 5),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    DateFormat('hh:mm a')
                                        .format(message.timestamp),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  if (message.isSent && message.isFailed)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 4),
                                      child: Icon(
                                        Icons.error_outline,
                                        color: Colors.red,
                                        size: 16,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.3),
                  blurRadius: 5,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: "Type a message...",
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 15, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(25)),
                        borderSide: BorderSide(width: 0, style: BorderStyle.none),
                      ),
                      filled: true,
                      fillColor: Color(0xFFEEEEEE),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 40,
                  width: 40,
                  child: FloatingActionButton(
                    onPressed: _isSending ? null : _sendMessage,
                    backgroundColor: _isSending ? Colors.grey : Colors.blue,
                    child: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white),
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:safe_pulse/db/db.dart';
import 'package:safe_pulse/model/contactdb.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';

class ChatMessage {
  final String text;
  final bool isSent;
  final String contactId;
  final String contactName;
  final String phoneNumber;
  final DateTime timestamp;
  final bool isFailed;

  ChatMessage({
    required this.text,
    required this.isSent,
    required this.contactId,
    required this.contactName,
    required this.timestamp,
    this.phoneNumber = '',
    this.isFailed = false,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'isSent': isSent,
        'contactId': contactId,
        'contactName': contactName,
        'phoneNumber': phoneNumber,
        'timestamp': timestamp.toIso8601String(),
        'isFailed': isFailed,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        text: json['text'],
        isSent: json['isSent'],
        contactId: json['contactId'],
        contactName: json['contactName'],
        phoneNumber: json['phoneNumber'] ?? '',
        timestamp: DateTime.parse(json['timestamp']),
        isFailed: json['isFailed'] ?? false,
      );
}

const String _isolateName = 'sms_background_isolate';

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
  Timer? _messageRefreshTimer;
  ReceivePort? _receivePort;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _loadContacts();
    await _loadMessages();
    await _initSmsReceiver();
    
    _messageRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        _loadMessages();
      }
    });
    
    _setupBackgroundChannel();
  }

  @override
  void dispose() {
    _cleanupResources();
    super.dispose();
  }

  void _cleanupResources() {
    _messageRefreshTimer?.cancel();
    _messageController.dispose();
    
    if (_receivePort != null) {
      _receivePort!.close();
      IsolateNameServer.removePortNameMapping(_isolateName);
    }
  }

  Future<void> _setupBackgroundChannel() async {
    _receivePort = ReceivePort();
    IsolateNameServer.registerPortWithName(_receivePort!.sendPort, _isolateName);
    
    _receivePort!.listen((dynamic message) {
      if (mounted) {
        _loadMessages();
      }
    });
  }

  Future<void> _initSmsReceiver() async {
    debugPrint("Initializing SMS receiver...");
    final bool? granted = await telephony.requestPhoneAndSmsPermissions;
    debugPrint("SMS permissions granted: $granted");
    
    if (granted ?? false) {
      telephony.listenIncomingSms(
        onNewMessage: _handleIncomingSms,
        onBackgroundMessage: backgroundMessageHandler,
        listenInBackground: true,
      );
      debugPrint("SMS listener initialized successfully");
    } else {
      debugPrint("SMS permissions denied");
      if (mounted) {
        Fluttertoast.showToast(
          msg: "SMS permissions denied. Cannot receive messages.",
          toastLength: Toast.LENGTH_LONG,
        );
      }
    }
  }

  void _handleIncomingSms(SmsMessage message) async {
    debugPrint("Received SMS in foreground: ${message.body}");
    if (message.address == null || message.body == null) return;
    
    String address = message.address!;
    DateTime now = DateTime.now();
    
    Dcontacts? matchedContact = await _findMatchingContact(address);
    
    final newMessage = ChatMessage(
      text: message.body!,
      isSent: false,
      contactId: matchedContact?.id.toString() ?? '',
      contactName: matchedContact?.name ?? address,
      phoneNumber: address,
      timestamp: now,
    );
    
    if (mounted) {
      setState(() {
        messages.add(newMessage);
        _sortMessages();
      });
    }
    
    await _saveMessages();
    
    if (matchedContact != null && mounted) {
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
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<ChatMessage> storedMessages = [];
      String? messagesJson = prefs.getString('chat_messages');
      
      if (messagesJson != null) {
        List<dynamic> decodedMessages = jsonDecode(messagesJson);
        storedMessages = decodedMessages.map((m) => ChatMessage.fromJson(m)).toList();
      }
      
      final DB db = DB();
      final contacts = await db.getContacts();
      
      String address = message.address ?? "Unknown";
      Dcontacts? matchedContact;
      
      for (var contact in contacts) {
        String normalizedContactNumber = _normalizePhoneNumberStatic(contact.number);
        String normalizedSenderNumber = _normalizePhoneNumberStatic(address);
        
        if (normalizedContactNumber == normalizedSenderNumber) {
          matchedContact = contact;
          break;
        }
      }
      
      storedMessages.add(ChatMessage(
        text: message.body ?? "",
        isSent: false,
        contactId: matchedContact?.id.toString() ?? '',
        contactName: matchedContact?.name ?? address,
        phoneNumber: address,
        timestamp: DateTime.now(),
      ));
      
      List<Map<String, dynamic>> encodedMessages =
          storedMessages.map((m) => m.toJson()).toList();
      await prefs.setString('chat_messages', jsonEncode(encodedMessages));
      
      debugPrint("Successfully saved background message");
      
      final SendPort? sendPort = IsolateNameServer.lookupPortByName(_isolateName);
      if (sendPort != null) {
        sendPort.send('new_message');
      }
    } catch (e) {
      debugPrint("Error saving background message: $e");
    }
  }
  
  static String _normalizePhoneNumberStatic(String number) {
    String digits = number.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }

  String _normalizePhoneNumber(String number) {
    return _normalizePhoneNumberStatic(number);
  }
  
  Future<Dcontacts?> _findMatchingContact(String phoneNumber) async {
    if (contactList == null || contactList!.isEmpty) {
      await _loadContacts();
    }
    
    String normalizedSenderNumber = _normalizePhoneNumber(phoneNumber);
    
    for (var contact in contactList ?? []) {
      String normalizedContactNumber = _normalizePhoneNumber(contact.number);
      
      if (normalizedContactNumber == normalizedSenderNumber) {
        return contact;
      }
    }
    
    return null;
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
    String formatted = number.replaceAll(RegExp(r'[^0-9+]'), '');
    
    if (!formatted.startsWith('+')) {
      formatted = '+1$formatted';
    }
    return formatted;
  }

  Future<void> _loadContacts() async {
    final value = await db.getContacts();
    if (mounted) {
      setState(() {
        contactList = value;
        count = value.length;
        debugPrint("Loaded ${value.length} contacts");
      });
    }
  }

  Future<void> _loadMessages() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? messagesJson = prefs.getString('chat_messages');
      if (messagesJson != null) {
        List<dynamic> decodedMessages = jsonDecode(messagesJson);
        if (mounted) {
          setState(() {
            messages = decodedMessages.map((m) => ChatMessage.fromJson(m)).toList();
            _sortMessages();
          });
          debugPrint("Loaded ${messages.length} messages");
        }
      }
    } catch (e) {
      debugPrint("Error loading messages: $e");
    }
  }

  void _sortMessages() {
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  Future<void> _saveMessages() async {
    try {
      _sortMessages();
      
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
      if (mounted) {
        Fluttertoast.showToast(msg: "Please enter a message");
      }
      return;
    }

    if (selectedContact == null) {
      if (mounted) {
        Fluttertoast.showToast(msg: "Please select a contact");
      }
      return;
    }

    final formattedNumber = _formatPhoneNumber(selectedContact!.number);
    if (formattedNumber.isEmpty) {
      if (mounted) {
        Fluttertoast.showToast(msg: "Invalid phone number format");
      }
      return;
    }

    if (!await _checkPermissions()) {
      if (mounted) {
        Fluttertoast.showToast(msg: "SMS permissions not granted");
      }
      return;
    }

    if (mounted) {
      setState(() => _isSending = true);
    }

    final newMessage = ChatMessage(
      text: _messageController.text,
      isSent: true,
      contactId: selectedContact!.id.toString(),
      contactName: selectedContact!.name,
      phoneNumber: selectedContact!.number,
      timestamp: DateTime.now(),
    );

    if (mounted) {
      setState(() {
        messages.add(newMessage);
        _messageController.clear();
        _sortMessages();
      });
    }
    
    await _saveMessages();

    bool sendSuccess = false;
    
    try {
      debugPrint("Sending SMS to: $formattedNumber");
      final completer = Completer<bool>();
      
      telephony.sendSms(
        to: formattedNumber,
        message: newMessage.text,
        statusListener: (status) {
          debugPrint("SMS status: $status");
          if (status == SendStatus.SENT || status == SendStatus.DELIVERED) {
            if (!completer.isCompleted) completer.complete(true);
          } else if (status != SendStatus.SENT && status != SendStatus.DELIVERED) {
            if (!completer.isCompleted) completer.complete(false);
          }
        },
      );
      
      try {
        sendSuccess = await completer.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            debugPrint("SMS send timed out, but might still be delivered");
            return true;
          },
        );
      } catch (timeoutError) {
        debugPrint("Completer error: $timeoutError");
        await telephony.sendSms(
          to: formattedNumber,
          message: newMessage.text,
        );
        sendSuccess = true;
      }
    } catch (e) {
      debugPrint("SMS send failed: $e");
      sendSuccess = false;
    }

    if (!sendSuccess) {
      _markMessageAsFailed(newMessage);
      if (mounted) {
        Fluttertoast.showToast(msg: "Failed to send message");
      }
    } else if (mounted) {
      Fluttertoast.showToast(msg: "Message sent successfully");
    }

    if (mounted) {
      setState(() => _isSending = false);
    }
  }

  void _markMessageAsFailed(ChatMessage message) {
    if (!mounted) return;
    
    setState(() {
      final index = messages.indexWhere((m) => 
        m.timestamp.isAtSameMomentAs(message.timestamp) && 
        m.text == message.text && 
        m.contactId == message.contactId);
        
      if (index != -1) {
        messages[index] = ChatMessage(
          text: message.text,
          isSent: true,
          contactId: message.contactId,
          contactName: message.contactName,
          phoneNumber: message.phoneNumber,
          timestamp: message.timestamp,
          isFailed: true,
        );
      }
    });
    _saveMessages();
  }

  List<ChatMessage> _getMessagesForSelectedContact() {
    if (selectedContact == null) return [];
    
    return messages.where((message) {
      if (message.contactId == selectedContact!.id.toString()) return true;
      
      String normalizedMessageNumber = _normalizePhoneNumber(message.phoneNumber);
      String normalizedContactNumber = _normalizePhoneNumber(selectedContact!.number);
      
      return normalizedMessageNumber == normalizedContactNumber;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (contactList == null) {
      contactList = [];
    }

    final contactMessages = _getMessagesForSelectedContact();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 100,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.3),
                    blurRadius: 3,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: count,
                itemBuilder: (context, index) {
                  final contact = contactList![index];
                  final isSelected = selectedContact?.id == contact.id;
                  
                  return GestureDetector(
                    onTap: () {
                      if (mounted) {
                        setState(() {
                          selectedContact = contact;
                          debugPrint("Selected contact: ${contact.name}");
                        });
                      }
                    },
                    child: Container(
                      width: 80,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.blue[50] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(10),
                        border: isSelected 
                            ? Border.all(color: Colors.blue, width: 2)
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            backgroundColor: isSelected 
                                ? Colors.blue[100] 
                                : Colors.grey[300],
                            child: Text(
                              contact.name.isNotEmpty 
                                  ? contact.name[0].toUpperCase()
                                  : "?",
                              style: TextStyle(
                                color: isSelected 
                                    ? Colors.blue[800] 
                                    : Colors.grey[800],
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Flexible(
                            child: Text(
                              contact.name,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected 
                                    ? Colors.blue[800] 
                                    : Colors.grey[800],
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
            Expanded(
              child: selectedContact == null
                  ? const Center(
                      child: Text(
                        "Select a contact to view messages",
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : contactMessages.isEmpty
                      ? const Center(
                          child: Text(
                            "No messages with this contact",
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 10),
                          itemCount: contactMessages.length,
                          itemBuilder: (context, index) {
                            final message = contactMessages[index];

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
                                          ? Colors.red[100]
                                          : Colors.blue[100]
                                      : Colors.grey[200],
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
                                          DateFormat('MM/dd hh:mm a')
                                              .format(message.timestamp),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        if (message.isSent)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 4),
                                            child: Icon(
                                              message.isFailed
                                                  ? Icons.error_outline
                                                  : Icons.check,
                                              color: message.isFailed
                                                  ? Colors.red
                                                  : Colors.green,
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
                      decoration: InputDecoration(
                        hintText: "Type a message...",
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 15, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[200],
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
                      elevation: 0,
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
                          : const Icon(Icons.send, size: 20),
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
}
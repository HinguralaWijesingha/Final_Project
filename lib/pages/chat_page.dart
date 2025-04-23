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
  final String? smsId;

  ChatMessage({
    required this.text,
    required this.isSent,
    required this.contactId,
    required this.contactName,
    required this.timestamp,
    this.phoneNumber = '',
    this.isFailed = false,
    this.smsId,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'isSent': isSent,
        'contactId': contactId,
        'contactName': contactName,
        'phoneNumber': phoneNumber,
        'timestamp': timestamp.toIso8601String(),
        'isFailed': isFailed,
        'smsId': smsId,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        text: json['text'],
        isSent: json['isSent'],
        contactId: json['contactId'],
        contactName: json['contactName'],
        phoneNumber: json['phoneNumber'] ?? '',
        timestamp: DateTime.parse(json['timestamp']),
        isFailed: json['isFailed'] ?? false,
        smsId: json['smsId'],
      );
}

const String _isolateName = 'sms_background_isolate';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final DB db = DB();
  List<Dcontacts>? contactList = [];
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
    _receivePort?.close();
    IsolateNameServer.removePortNameMapping(_isolateName);
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
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? messagesJson = prefs.getString('chat_messages');
      final List<ChatMessage> storedMessages = messagesJson != null
          ? (jsonDecode(messagesJson) as List<dynamic>)
              .map((m) => ChatMessage.fromJson(m))
              .toList()
          : [];
      
      final DB db = DB();
      final List<Dcontacts> contacts = await db.getContacts();
      
      final String address = message.address ?? "Unknown";
      Dcontacts? matchedContact;
      
      for (final contact in contacts) {
        final String normalizedContactNumber = _normalizePhoneNumberStatic(contact.number);
        final String normalizedSenderNumber = _normalizePhoneNumberStatic(address);
        
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
      
      final List<Map<String, dynamic>> encodedMessages = storedMessages.map((m) => m.toJson()).toList();
      await prefs.setString('chat_messages', jsonEncode(encodedMessages));
      
      debugPrint("Successfully saved background message");
      
      final SendPort? sendPort = IsolateNameServer.lookupPortByName(_isolateName);
      sendPort?.send('new_message');
    } catch (e) {
      debugPrint("Error saving background message: $e");
    }
  }
  
  static String _normalizePhoneNumberStatic(String number) {
    final String digits = number.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }

  String _normalizePhoneNumber(String number) {
    return _normalizePhoneNumberStatic(number);
  }
  
  Future<Dcontacts?> _findMatchingContact(String phoneNumber) async {
    if (contactList == null || contactList!.isEmpty) {
      await _loadContacts();
    }
    
    final String normalizedSenderNumber = _normalizePhoneNumber(phoneNumber);
    
    for (final contact in contactList ?? []) {
      final String normalizedContactNumber = _normalizePhoneNumber(contact.number);
      if (normalizedContactNumber == normalizedSenderNumber) {
        return contact;
      }
    }
    
    return null;
  }

  Future<bool> _checkPermissions() async {
    try {
      final bool? smsGranted = await telephony.requestSmsPermissions;
      final bool? phoneGranted = await telephony.requestPhonePermissions;
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
    final List<Dcontacts> value = await db.getContacts();
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
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? messagesJson = prefs.getString('chat_messages');
      if (messagesJson != null) {
        final List<dynamic> decodedMessages = jsonDecode(messagesJson);
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
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> encodedMessages = messages.map((m) => m.toJson()).toList();
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

    final String formattedNumber = _formatPhoneNumber(selectedContact!.number);
    if (formattedNumber.isEmpty) {
      Fluttertoast.showToast(msg: "Invalid phone number format");
      return;
    }

    if (!await _checkPermissions()) {
      Fluttertoast.showToast(msg: "SMS permissions not granted");
      return;
    }

    setState(() => _isSending = true);

    final ChatMessage newMessage = ChatMessage(
      text: _messageController.text,
      isSent: true,
      contactId: selectedContact!.id.toString(),
      contactName: selectedContact!.name,
      phoneNumber: selectedContact!.number,
      timestamp: DateTime.now(),
    );

    setState(() {
      messages.add(newMessage);
      _messageController.clear();
      _sortMessages();
    });
    
    await _saveMessages();

    bool sendSuccess = false;
    String? smsId;
    
    try {
      debugPrint("Sending SMS to: $formattedNumber");
      
      final Completer<bool> completer = Completer<bool>();
      
      await telephony.sendSms(
        to: formattedNumber,
        message: newMessage.text,
        statusListener: (SendStatus status) {
          debugPrint("SMS status: $status");
          if (status == SendStatus.SENT || status == SendStatus.DELIVERED) {
            if (!completer.isCompleted) completer.complete(true);
          //} else if (status == SendStatus.) {  
            //if (!completer.isCompleted) completer.complete(false);
          }
        },
      );

      sendSuccess = await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint("SMS send timed out, but might still be delivered");
          return true;
        },
      );
    } catch (e) {
      debugPrint("SMS send failed: $e");
      sendSuccess = false;
    }

    setState(() {
      final int index = messages.indexWhere((m) => 
        m.timestamp.isAtSameMomentAs(newMessage.timestamp));
      if (index != -1) {
        messages[index] = ChatMessage(
          text: newMessage.text,
          isSent: true,
          contactId: newMessage.contactId,
          contactName: newMessage.contactName,
          phoneNumber: newMessage.phoneNumber,
          timestamp: newMessage.timestamp,
          isFailed: !sendSuccess,
          smsId: smsId,
        );
      }
    });
    
    await _saveMessages();

    Fluttertoast.showToast(
      msg: sendSuccess ? "Message sent successfully" : "Failed to send message",
    );

    setState(() => _isSending = false);
  }

  void _markMessageAsFailed(ChatMessage message) {
    if (!mounted) return;
    
    setState(() {
      final int index = messages.indexWhere((m) => 
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
      
      final String normalizedMessageNumber = _normalizePhoneNumber(message.phoneNumber);
      final String normalizedContactNumber = _normalizePhoneNumber(selectedContact!.number);
      
      return normalizedMessageNumber == normalizedContactNumber;
    }).toList();
  }

  Widget _buildMessageWidget(BuildContext context, ChatMessage message) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
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
          Text(message.text, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 5),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat('MM/dd hh:mm a').format(message.timestamp),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              if (message.isSent)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    message.isFailed ? Icons.error_outline : Icons.check,
                    color: message.isFailed ? Colors.red : Colors.green,
                    size: 16,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<ChatMessage> contactMessages = _getMessagesForSelectedContact();

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
                      setState(() {
                        selectedContact = contact;
                        debugPrint("Selected contact: ${contact.name}");
                      });
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
                              child: _buildMessageWidget(context, message),
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
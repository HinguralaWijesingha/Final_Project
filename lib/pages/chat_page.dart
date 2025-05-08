import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:safe_pulse/db/db.dart';
import 'package:safe_pulse/model/contactdb.dart';
import 'package:safe_pulse/model/message_model.dart';
import 'package:intl/intl.dart';
import 'package:flutter_sms/flutter_sms.dart'; 
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

import 'package:safe_pulse/text/sms.dart';

class ChatPage extends StatefulWidget {
  final int contactId;

  const ChatPage({Key? key, required this.contactId}) : super(key: key);

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final DB _db = DB();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  Dcontacts? _contact;
  List<Message> _messages = [];
  bool _isSendingMessage = false;
  bool _smsPermissionGranted = false;
  StreamSubscription<Message>? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _loadContact();
    _loadMessages();
    _checkPermissions();
    _setupMessageListener();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    final status = await Permission.sms.status;
    setState(() {
      _smsPermissionGranted = status.isGranted;
    });
  }

  Future<void> _loadContact() async {
    try {
      final contact = await _db.getContactById(widget.contactId);
      setState(() {
        _contact = contact;
      });
    } catch (e) {
      Fluttertoast.showToast(msg: "Error loading contact: $e");
      Navigator.pop(context);
    }
  }

  Future<void> _loadMessages() async {
    try {
      final messages = await _db.getMessagesForContact(widget.contactId);
      setState(() {
        _messages = messages;
      });
      _scrollToBottom();
    } catch (e) {
      Fluttertoast.showToast(msg: "Error loading messages: $e");
    }
  }

  void _setupMessageListener() {
    _messageSubscription = SMSService().messageStream.listen((message) {
      if (message.contactId == widget.contactId) {
        _loadMessages();
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _isSendingMessage) return;
    
    setState(() {
      _isSendingMessage = true;
    });

    try {
      final now = DateTime.now();
      final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
      final messageContent = _messageController.text;
      
      final message = Message(
        widget.contactId,
        messageContent,
        timestamp,
        true,
      );
      await _db.insertMessage(message);

      if (_contact != null) {
        if (!_smsPermissionGranted) {
          final status = await Permission.sms.request();
          setState(() {
            _smsPermissionGranted = status.isGranted;
          });
        }

        if (_smsPermissionGranted) {
          try {
            await _sendSMS(messageContent, [_contact!.number]);
            Fluttertoast.showToast(msg: "Message sent");
          } catch (e) {
            Fluttertoast.showToast(
              msg: "Message saved but couldn't send SMS: $e",
              toastLength: Toast.LENGTH_LONG,
            );
          }
        } else {
          Fluttertoast.showToast(
            msg: "Message saved but SMS permission denied",
            toastLength: Toast.LENGTH_LONG,
          );
        }
      }

      _messageController.clear();
      await _loadMessages();

    } catch (e) {
      Fluttertoast.showToast(
        msg: "Error: ${e.toString()}",
        toastLength: Toast.LENGTH_LONG,
      );
    } finally {
      setState(() {
        _isSendingMessage = false;
      });
    }
  }

  Future<void> _sendSMS(String message, List<String> recipients) async {
    try {
      String result = await sendSMS(
        message: message,
        recipients: recipients,
        sendDirect: true,
      );
      print("SMS Result: $result");
    } catch (error) {
      print("Error sending SMS: $error");
      throw error;
    }
  }

  Widget _buildMessageBubble(Message message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: Align(
        alignment: message.isFromMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: message.isFromMe ? Colors.blue : Colors.grey[300],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.content,
                style: TextStyle(
                  color: message.isFromMe ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('HH:mm').format(
                  DateFormat('yyyy-MM-dd HH:mm:ss').parse(message.timestamp)
                ),
                style: TextStyle(
                  fontSize: 10,
                  color: message.isFromMe ? Colors.white70 : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_contact?.name ?? "Chat"),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadMessages,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length,
              padding: const EdgeInsets.all(8),
              itemBuilder: (context, index) {
                return _buildMessageBubble(_messages[index]);
              },
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
                      hintText: "Type a message...",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    minLines: 1,
                    maxLines: 3,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
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
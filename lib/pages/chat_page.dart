import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:safe_pulse/db/db.dart';
import 'package:safe_pulse/model/contactdb.dart';
import 'package:safe_pulse/model/message_model.dart';
import 'package:intl/intl.dart';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

class ChatPage extends StatefulWidget {
  final int contactId;

  const ChatPage({Key? key, required this.contactId}) : super(key: key);

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final DB _db = DB();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  StreamSubscription? _smsSubscription;
  
  Dcontacts? _contact;
  List<Message> _messages = [];
  bool _isSendingMessage = false;
  bool _smsPermissionGranted = false;
  bool _isPageActive = true;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeChat();
    if (_isAndroid) {
      _initSmsListener();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isPageActive = state == AppLifecycleState.resumed;
    if (_isPageActive) {
      _loadMessages();
    }
  }

  Future<void> _initializeChat() async {
    await _loadContact();
    await _loadMessages();
    await _checkPermissions();
  }

  void _initSmsListener() {
    _smsSubscription = EventChannel('sms_receiver/events')
        .receiveBroadcastStream()
        .listen((dynamic event) {
          try {
            final sms = event as Map<dynamic, dynamic>;
            final sender = sms['sender'].toString();
            final message = sms['message'].toString();
            
            if (_isFromCurrentContact(sender)) {
              _addMessageToChat(message, false);
              HapticFeedback.lightImpact();
            }
          } catch (e) {
            print('Error processing SMS: $e');
          }
        }, onError: (error) {
          print('SMS Receiver error: $error');
          Fluttertoast.showToast(
            msg: "SMS monitoring error",
            backgroundColor: Colors.red,
          );
        });
  }

  bool _isFromCurrentContact(String sender) {
    if (_contact == null) return false;
    return _normalizeNumber(sender) == _normalizeNumber(_contact!.number);
  }

  String _normalizeNumber(String number) {
    return number.replaceAll(RegExp(r'[^0-9+]'), '');
  }

  Future<void> _addMessageToChat(String content, bool isFromMe) async {
    final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final message = Message(
      widget.contactId,
      content,
      timestamp,
      isFromMe,
    );

    await _db.insertMessage(message);

    if (mounted) {
      setState(() {
        _messages.add(message);
      });
      _scrollToBottom();
      
      if (!isFromMe && !_isPageActive) {
        Fluttertoast.showToast(
          msg: "New message from ${_contact?.name}",
          backgroundColor: Colors.green,
          textColor: Colors.white,
          toastLength: Toast.LENGTH_LONG,
        );
      }
    }
  }

  @override
  void dispose() {
    _smsSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    if (_isAndroid) {
      final status = await Permission.sms.status;
      setState(() {
        _smsPermissionGranted = status.isGranted;
      });
      
      if (!_smsPermissionGranted) {
        final result = await Permission.sms.request();
        setState(() {
          _smsPermissionGranted = result.isGranted;
        });
        
        if (!result.isGranted) {
          Fluttertoast.showToast(
            msg: "SMS permissions required for full functionality",
            toastLength: Toast.LENGTH_LONG,
          );
        }
      }
    }
  }

  Future<void> _loadContact() async {
    try {
      final contact = await _db.getContactById(widget.contactId);
      setState(() {
        _contact = contact;
      });
    } catch (e) {
      Fluttertoast.showToast(msg: "Error loading contact: $e");
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _loadMessages() async {
    try {
      final messages = await _db.getMessagesForContact(widget.contactId);
      setState(() {
        _messages = messages;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      Fluttertoast.showToast(msg: "Error loading messages: $e");
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final messageContent = _messageController.text.trim();
    if (messageContent.isEmpty || _isSendingMessage) return;
    
    setState(() {
      _isSendingMessage = true;
    });

    try {
      await _addMessageToChat(messageContent, true);
      
      if (_isAndroid && _contact != null) {
        if (!_smsPermissionGranted) {
          await _checkPermissions();
        }

        if (_smsPermissionGranted) {
          try {
            await _sendSMS(messageContent, [_contact!.number]);
            Fluttertoast.showToast(msg: "Message sent");
          } catch (e) {
            Fluttertoast.showToast(
              msg: "Message saved but couldn't send SMS",
              toastLength: Toast.LENGTH_LONG,
            );
          }
        }
      }

      _messageController.clear();
    } catch (e) {
      Fluttertoast.showToast(
        msg: "Error: ${e.toString()}",
        toastLength: Toast.LENGTH_LONG,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSendingMessage = false;
        });
      }
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
    final isMe = message.isFromMe;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMe ? Colors.blue : Colors.grey[300],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.content,
                  style: TextStyle(
                    color: isMe ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('HH:mm').format(
                    DateFormat('yyyy-MM-dd HH:mm:ss').parse(message.timestamp)
                  ),
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe ? Colors.white70 : Colors.grey[600],
                  ),
                ),
              ],
            ),
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
          if (!_smsPermissionGranted && _isAndroid)
            IconButton(
              icon: const Icon(Icons.warning, color: Colors.orange),
              onPressed: _checkPermissions,
              tooltip: "SMS permissions required",
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      "No messages yet",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
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
                  backgroundColor: _isSendingMessage ? Colors.grey : Colors.blue,
                  child: IconButton(
                    icon: _isSendingMessage
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send, color: Colors.white),
                    onPressed: _isSendingMessage ? null : _sendMessage,
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
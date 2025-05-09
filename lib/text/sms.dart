import 'package:safe_pulse/db/db.dart';
import 'package:safe_pulse/model/contactdb.dart';
import 'package:safe_pulse/model/message_model.dart';
import 'package:telephony/telephony.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

class SMSService {
  static final SMSService _instance = SMSService._internal();
  final Telephony telephony = Telephony.instance;
  final DB db = DB();
  final StreamController<Message> _messageStreamController = 
      StreamController<Message>.broadcast();
  
  bool _isInitialized = false;
  bool _permissionsGranted = false;

  factory SMSService() => _instance;
  
  SMSService._internal();

  Stream<Message> get messageStream => _messageStreamController.stream;
  bool get isInitialized => _isInitialized;
  bool get permissionsGranted => _permissionsGranted;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    debugPrint('Initializing SMS Service...');
    
    try {
      // Request SMS permissions
      _permissionsGranted = await telephony.requestPhoneAndSmsPermissions ?? false;
      
      if (_permissionsGranted) {
        debugPrint('SMS permissions granted');
        
        // Register SMS listeners
        telephony.listenIncomingSms(
          onNewMessage: _onMessageReceived,
          onBackgroundMessage: backgroundMessageHandler,
          listenInBackground: true,
        );
        
        _isInitialized = true;
        await _checkForNewMessages();
      } else {
        debugPrint('SMS permissions denied');
      }
    } catch (e) {
      debugPrint('Error initializing SMS Service: $e');
      _isInitialized = false;
      _permissionsGranted = false;
    }
  }

  Future<void> _checkForNewMessages() async {
    try {
      // Get all SMS messages from the device
      final messages = await telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );
      
      // Limit to most recent 50 messages for performance
      final recentMessages = messages.length > 50 ? messages.sublist(0, 50) : messages;
      debugPrint('Processing ${recentMessages.length} recent messages');
      
      // Process messages in reverse order (oldest first)
      for (var sms in recentMessages.reversed) {
        await _processMessage(
          sms.address ?? '', 
          sms.body ?? '', 
          DateTime.fromMillisecondsSinceEpoch(sms.date ?? DateTime.now().millisecondsSinceEpoch)
        );
      }
    } catch (e) {
      debugPrint('Error checking for new messages: $e');
    }
  }
  
  Future<void> _onMessageReceived(SmsMessage message) async {
    await _processMessage(
      message.address ?? '', 
      message.body ?? '', 
      DateTime.now()
    );
  }
  
  Future<void> _processMessage(String sender, String body, DateTime timestamp) async {
    debugPrint('Processing SMS from: $sender with body: ${body.substring(0, min(10, body.length))}...');
    
    try {
      final normalizedSender = _normalizePhoneNumber(sender);
      final contacts = await db.getContacts();
      
      // Find matching contact
      Dcontacts? matchedContact;
      for (var contact in contacts) {
        if (_isNumberMatch(_normalizePhoneNumber(contact.number), normalizedSender)) {
          matchedContact = contact;
          break;
        }
      }
      
      if (matchedContact != null) {
        final formattedTimestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp);
        
        final newMessage = Message(
          matchedContact.id,
          body,
          formattedTimestamp,
          false,
        );
        
        // Save to database and notify listeners
        await db.insertMessage(newMessage);
        _messageStreamController.add(newMessage);
        
        debugPrint('Message processed and saved for contact: ${matchedContact.name}');
      } else {
        debugPrint('No contact match found for sender: $sender');
      }
    } catch (e) {
      debugPrint('Error processing message: $e');
    }
  }
  
  bool _isNumberMatch(String contactNumber, String senderNumber) {
    // Check if either number ends with the other (accounting for different formats)
    return contactNumber.endsWith(senderNumber) || 
           senderNumber.endsWith(contactNumber);
  }
  
  String _normalizePhoneNumber(String phoneNumber) {
    // Remove all non-digit characters
    String digitsOnly = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    
    // Remove country code if present (keep last 10 digits)
    if (digitsOnly.length > 10) {
      return digitsOnly.substring(digitsOnly.length - 10);
    }
    
    return digitsOnly;
  }
  
  Future<void> dispose() async {
    await _messageStreamController.close();
    _isInitialized = false;
  }

  // Helper to get the minimum of two integers
  static int min(int a, int b) => a < b ? a : b;
}

@pragma('vm:entry-point')
Future<void> backgroundMessageHandler(SmsMessage message) async {
  debugPrint('Background message handler triggered');
  await SMSService()._processMessage(
    message.address ?? '', 
    message.body ?? '', 
    DateTime.now()
  );
}
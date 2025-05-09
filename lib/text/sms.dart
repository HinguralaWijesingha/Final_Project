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
  final StreamController<Message> _messageStreamController = StreamController<Message>.broadcast();
  
  bool _isInitialized = false;

  factory SMSService() {
    return _instance;
  }
  
  SMSService._internal();

  Stream<Message> get messageStream => _messageStreamController.stream;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    debugPrint('Initializing SMS Service...');
    
    // Request SMS permissions
    bool? permissionsGranted = await telephony.requestPhoneAndSmsPermissions;
    
    if (permissionsGranted == true) {
      debugPrint('SMS permissions granted');
      // Register SMS listener for both foreground and background messages
      telephony.listenIncomingSms(
        onNewMessage: _onMessageReceived,
        onBackgroundMessage: backgroundMessageHandler,
        listenInBackground: true,
      );
      _isInitialized = true;
      
      // Also check for any new messages that might have arrived
      // while the app was closed
      _checkForNewMessages();
    } else {
      debugPrint('SMS permissions denied');
    }
  }

  Future<void> _checkForNewMessages() async {
    try {
      // This method could query for any messages received while the app was closed
      // For now, we'll just log that we're checking
      debugPrint('Checking for messages received while app was closed');
    } catch (e) {
      debugPrint('Error checking for new messages: $e');
    }
  }
  
  Future<void> _onMessageReceived(SmsMessage message) async {
    debugPrint('Received SMS from: ${message.address} with body: ${message.body?.substring(0, min(10, message.body?.length ?? 0))}...');
    
    if (message.address == null || message.body == null) {
      debugPrint('Invalid message - missing address or body');
      return;
    }
    
    try {
      List<Dcontacts> contacts = await db.getContacts();
      debugPrint('Checking against ${contacts.length} contacts');
      
      Dcontacts? matchedContact;
      
      for (var contact in contacts) {
        String normalizedContactNumber = _normalizePhoneNumber(contact.number);
        String normalizedSenderNumber = _normalizePhoneNumber(message.address!);
        
        debugPrint('Comparing contact: $normalizedContactNumber with sender: $normalizedSenderNumber');
        
        // Check if either number ends with the other, accounting for different formats
        if (normalizedContactNumber.endsWith(normalizedSenderNumber) || 
            normalizedSenderNumber.endsWith(normalizedContactNumber)) {
          matchedContact = contact;
          debugPrint('Match found! Contact: ${contact.name}');
          break;
        }
      }
      
      if (matchedContact != null) {
        debugPrint('Matched contact: ${matchedContact.name} (ID: ${matchedContact.id})');
        
        final now = DateTime.now();
        final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
        
        final newMessage = Message(
          matchedContact.id,
          message.body!,
          timestamp,
          false,
        );
        
        await db.insertMessage(newMessage);
        debugPrint('Message saved to database with timestamp: $timestamp');
        
        // Broadcast the new message to all listeners
        _messageStreamController.add(newMessage);
        debugPrint('Message broadcast to stream listeners');
      } else {
        debugPrint('No matching contact found for number: ${message.address}');
      }
    } catch (e) {
      debugPrint('Error processing incoming message: $e');
    }
  }
  
  String _normalizePhoneNumber(String phoneNumber) {
    // Remove all non-digit characters
    String digitsOnly = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    
    // Remove country code if present (assuming country codes are 1-3 digits)
    // This is a simplified approach - a more robust solution would consider specific country codes
    if (digitsOnly.length > 10) {
      return digitsOnly.substring(digitsOnly.length - 10);
    }
    
    return digitsOnly;
  }
  
  // Helper to get the minimum of two integers
  int min(int a, int b) {
    return a < b ? a : b;
  }
}

@pragma('vm:entry-point')
void backgroundMessageHandler(SmsMessage message) async {
  debugPrint('Background message handler triggered');
  await SMSService()._onMessageReceived(message);
}
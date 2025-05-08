import 'package:safe_pulse/db/db.dart';
import 'package:safe_pulse/model/contactdb.dart';
import 'package:safe_pulse/model/message_model.dart';
import 'package:telephony/telephony.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class SMSService {
  static final SMSService _instance = SMSService._internal();
  final Telephony telephony = Telephony.instance;
  final DB db = DB();
  final StreamController<Message> _messageStreamController = StreamController<Message>.broadcast();
  
  // Singleton pattern
  factory SMSService() {
    return _instance;
  }
  
  SMSService._internal();
  
  Stream<Message> get messageStream => _messageStreamController.stream;

  Future<void> initialize() async {
    // Request SMS permissions
    bool? permissionsGranted = await telephony.requestPhoneAndSmsPermissions;
    
    if (permissionsGranted ?? false) {
      print('SMS permissions granted');
      // Register SMS listener for background messages
      telephony.listenIncomingSms(
        onNewMessage: _onMessageReceived,
        onBackgroundMessage: backgroundMessageHandler,
        listenInBackground: true,
      );
    } else {
      print('SMS permissions denied');
    }
  }
  
  // Handler for incoming SMS messages
  Future<void> _onMessageReceived(SmsMessage message) async {
    print('Received SMS from: ${message.address}');
    
    if (message.address == null) return;
    
    // Try to find the contact in our database by phone number
    List<Dcontacts> contacts = await db.getContacts();
    Dcontacts? matchedContact;
    
    for (var contact in contacts) {
      // Normalize phone numbers for comparison
      String normalizedContactNumber = _normalizePhoneNumber(contact.number);
      String normalizedSenderNumber = _normalizePhoneNumber(message.address!);
      
      print('Comparing: $normalizedContactNumber with $normalizedSenderNumber');
      
      if (normalizedContactNumber == normalizedSenderNumber) {
        matchedContact = contact;
        break;
      }
    }
    
    // If we found a matching contact, save the message
    if (matchedContact != null) {
      print('Matched contact: ${matchedContact.name}');
      
      final now = DateTime.now();
      final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
      
      final newMessage = Message(
        matchedContact.id,
        message.body ?? "",
        timestamp,
        false, // isFromMe = false for incoming messages
      );
      
      await db.insertMessage(newMessage);
      _messageStreamController.add(newMessage);
    }
  }
  
  String _normalizePhoneNumber(String phoneNumber) {
    return phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
  }
}

@pragma('vm:entry-point')
void backgroundMessageHandler(SmsMessage message) async {
  print('Background message received from: ${message.address}');
  
  // Initialize DB and SMSService
  final db = DB();
  final smsService = SMSService();
  
  // Process the message
  if (message.address == null) return;
  
  List<Dcontacts> contacts = await db.getContacts();
  Dcontacts? matchedContact;
  
  for (var contact in contacts) {
    String normalizedContactNumber = smsService._normalizePhoneNumber(contact.number);
    String normalizedSenderNumber = smsService._normalizePhoneNumber(message.address!);
    
    if (normalizedContactNumber == normalizedSenderNumber) {
      matchedContact = contact;
      break;
    }
  }
  
  if (matchedContact != null) {
    final now = DateTime.now();
    final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    
    final newMessage = Message(
      matchedContact.id,
      message.body ?? "",
      timestamp,
      false,
    );
    
    await db.insertMessage(newMessage);
  }
}
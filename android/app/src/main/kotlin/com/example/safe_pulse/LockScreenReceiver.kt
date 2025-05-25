package com.example.safe_pulse

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.telephony.SmsManager
import android.util.Log
import org.json.JSONArray
import org.json.JSONException

class LockScreenReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "LockScreenReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            "com.example.safe_pulse.EMERGENCY_ACTION" -> {
                Log.d(TAG, "Emergency action triggered from lock screen")
                sendEmergencyAlertsDirectly(context)
                
                // Stop the emergency service after sending alerts
                context.stopService(Intent(context, EmergencyForegroundService::class.java))
            }
            
            "com.example.safe_pulse.FAKE_CALL_ACTION" -> {
                Log.d(TAG, "Fake call action triggered from lock screen")
                startFakeCall(context)
            }
            
            Intent.ACTION_SCREEN_OFF -> {
                Log.d(TAG, "Screen turned off")
                val serviceIntent = Intent(context, EmergencyForegroundService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            }
        }
    }

    private fun startFakeCall(context: Context) {
        try {
            val fakeCallIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("action", "start_fake_call")
            }
            context.startActivity(fakeCallIntent)
            Log.i(TAG, "Fake call started from lock screen")
        } catch (e: Exception) {
            Log.e(TAG, "Error starting fake call: ${e.message}", e)
        }
    }

    private fun sendEmergencyAlertsDirectly(context: Context) {
        try {
            val sharedPreferences = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val contactsJson = sharedPreferences.getString("flutter.emergency_contacts", null)
            
            if (contactsJson.isNullOrEmpty()) {
                Log.w(TAG, "No emergency contacts found")
                return
            }

            val contacts = parseContacts(contactsJson)
            if (contacts.isEmpty()) {
                Log.w(TAG, "No valid emergency contacts to send to")
                return
            }

            val message = "🚨 EMERGENCY ALERT 🚨\n" +
                    "I need immediate help!\n" +
                    "This is an automated message from SafePulse app.\n" +
                    "Sent from lock screen emergency mode."

            sendSmsToContacts(contacts, message)
            
            Log.i(TAG, "Emergency alerts sent to ${contacts.size} contacts")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error sending emergency alerts: ${e.message}", e)
        }
    }

    private fun parseContacts(contactsJson: String): List<String> {
        val contacts = mutableListOf<String>()
        try {
            val jsonArray = JSONArray(contactsJson)
            for (i in 0 until jsonArray.length()) {
                val contact = jsonArray.getJSONObject(i)
                val number = contact.getString("number")
                val cleanNumber = number.replace(Regex("[^0-9+]"), "")
                if (cleanNumber.isNotEmpty()) {
                    contacts.add(cleanNumber)
                }
            }
        } catch (e: JSONException) {
            Log.e(TAG, "Error parsing contacts JSON: ${e.message}", e)
        }
        return contacts
    }

    private fun sendSmsToContacts(contacts: List<String>, message: String) {
        try {
            val smsManager = SmsManager.getDefault()
            
            for (contact in contacts) {
                try {
                    // Split message if it's too long
                    val parts = smsManager.divideMessage(message)
                    if (parts.size == 1) {
                        smsManager.sendTextMessage(contact, null, message, null, null)
                    } else {
                        smsManager.sendMultipartTextMessage(contact, null, parts, null, null)
                    }
                    Log.d(TAG, "SMS sent to: $contact")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to send SMS to $contact: ${e.message}", e)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in sendSmsToContacts: ${e.message}", e)
        }
    }
}
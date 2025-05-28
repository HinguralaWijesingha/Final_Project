package com.example.safe_pulse

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.telephony.SmsManager
import android.util.Log
import androidx.core.app.ActivityCompat
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

    private fun triggerLocationSharing(context: Context) {
        try {
            // Set flag to activate location sharing
            val sharedPreferences = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val editor = sharedPreferences.edit()
            editor.putBoolean("flutter.emergency_location_sharing", true)
            editor.putLong("flutter.emergency_location_share_time", System.currentTimeMillis())
            editor.apply()
            
            Log.i(TAG, "Emergency location sharing activated")
        } catch (e: Exception) {
            Log.e(TAG, "Error activating location sharing: ${e.message}", e)
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

            // Get current location synchronously with last known location
            val location = getCurrentLocationSync(context)
            val locationText = if (location != null) {
                val osmUrl = "https://www.openstreetmap.org/?mlat=${location.latitude}&mlon=${location.longitude}&zoom=16"
                "\n📍 My location: $osmUrl\nCoordinates: ${location.latitude}, ${location.longitude}"
            } else {
                "\n⚠ Location unavailable"
            }

            val message = "🚨 EMERGENCY ALERT 🚨\n" +
                    "I need immediate help!\n" +
                    "This is an automated message from SafePulse app.\n" +
                    "Sent from lock screen emergency mode.$locationText"

            sendSmsToContacts(contacts, message)
            
            Log.i(TAG, "Emergency alerts sent to ${contacts.size} contacts with location info")
            
            // Also trigger location sharing
            triggerLocationSharing(context)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error sending emergency alerts: ${e.message}", e)
        }
    }

    private fun getCurrentLocationSync(context: Context): Location? {
        if (!hasLocationPermission(context)) {
            Log.w(TAG, "Location permission not granted")
            return null
        }

        try {
            val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            
            // Check if location services are enabled
            if (!locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) && 
                !locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                Log.w(TAG, "Location services are disabled")
                return null
            }

            var bestLocation: Location? = null
            
            // Try GPS first (more accurate)
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                try {
                    val gpsLocation = locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                    if (gpsLocation != null) {
                        bestLocation = gpsLocation
                        Log.d(TAG, "Got GPS location: ${gpsLocation.latitude}, ${gpsLocation.longitude}")
                    }
                } catch (e: SecurityException) {
                    Log.e(TAG, "GPS location access denied: ${e.message}")
                }
            }
            
            // Try Network location if GPS not available or not recent
            if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                try {
                    val networkLocation = locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                    if (networkLocation != null) {
                        // Use network location if no GPS location or if network location is more recent
                        if (bestLocation == null || 
                            (networkLocation.time > bestLocation.time && isLocationRecent(networkLocation))) {
                            bestLocation = networkLocation
                            Log.d(TAG, "Got Network location: ${networkLocation.latitude}, ${networkLocation.longitude}")
                        }
                    }
                } catch (e: SecurityException) {
                    Log.e(TAG, "Network location access denied: ${e.message}")
                }
            }
            
            // Try Passive provider as fallback
            try {
                val passiveLocation = locationManager.getLastKnownLocation(LocationManager.PASSIVE_PROVIDER)
                if (passiveLocation != null && bestLocation == null) {
                    bestLocation = passiveLocation
                    Log.d(TAG, "Got Passive location: ${passiveLocation.latitude}, ${passiveLocation.longitude}")
                }
            } catch (e: SecurityException) {
                Log.e(TAG, "Passive location access denied: ${e.message}")
            }

            if (bestLocation != null) {
                val age = (System.currentTimeMillis() - bestLocation.time) / 1000 / 60 // age in minutes
                Log.i(TAG, "Using location from ${age} minutes ago: ${bestLocation.latitude}, ${bestLocation.longitude}")
                return bestLocation
            } else {
                Log.w(TAG, "No location available from any provider")
                return null
            }

        } catch (e: Exception) {
            Log.e(TAG, "Exception getting location: ${e.message}", e)
            return null
        }
    }

    private fun hasLocationPermission(context: Context): Boolean {
        return ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
               ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
    }

    private fun isLocationRecent(location: Location): Boolean {
        val fifteenMinutesAgo = System.currentTimeMillis() - (15 * 60 * 1000)
        return location.time > fifteenMinutesAgo
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
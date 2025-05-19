package com.example.safe_pulse

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.telephony.SmsMessage
import android.util.Log
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    // Channel constants
    private companion object {
        const val SMS_CHANNEL = "sms_receiver"
        const val SMS_EVENT_CHANNEL = "sms_receiver/events"
        const val FILE_SHARE_CHANNEL = "safepulse/send_file"
        const val SMS_PERMISSION_CODE = 101
        const val TAG = "SafePulseSMS"
    }

    private var smsReceiver: BroadcastReceiver? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Method Channel for SMS permission requests
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestSmsPermissions" -> requestSmsPermissions(result)
                "hasSmsPermissions" -> result.success(hasSmsPermissions())
                else -> result.notImplemented()
            }
        }

        // Event Channel for receiving SMS
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    Log.d(TAG, "EventChannel listener attached")
                    eventSink = events
                    setupSmsReceiver()
                }

                override fun onCancel(arguments: Any?) {
                    Log.d(TAG, "EventChannel listener detached")
                    eventSink = null
                    unregisterSmsReceiver()
                }
            }
        )
        
        // Method Channel for file sharing functionality
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_SHARE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendFile" -> {
                    val filePath = call.argument<String>("filePath")
                    val recipients = call.argument<List<String>>("recipients")
                    val message = call.argument<String>("message")
                    
                    if (filePath != null && recipients != null && message != null) {
                        val success = sendFileViaIntent(filePath, recipients, message)
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGUMENTS", "Missing required arguments", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun setupSmsReceiver() {
        unregisterSmsReceiver()
        
        smsReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                Log.d(TAG, "Broadcast received: ${intent.action}")
                
                when (intent.action) {
                    "android.provider.Telephony.SMS_RECEIVED" -> {
                        processSystemSms(intent.extras)
                    }
                    "sms-received" -> {
                        processCustomSms(intent)
                    }
                }
            }

            private fun processSystemSms(bundle: Bundle?) {
                bundle ?: run {
                    Log.w(TAG, "Null bundle received in SMS intent")
                    return
                }

                try {
                    val pdus = getPdusFromBundle(bundle)
                    val format = bundle.getString("format")
                    
                    pdus.forEach { pdu ->
                        try {
                            createSmsMessage(pdu, format)?.let { message ->
                                forwardSmsToFlutter(
                                    sender = message.originatingAddress ?: "unknown",
                                    message = message.messageBody ?: "no content"
                                )
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error processing individual PDU", e)
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error processing SMS bundle", e)
                }
            }

            private fun getPdusFromBundle(bundle: Bundle): Array<ByteArray> {
                return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    bundle.getParcelableArray("pdus", ByteArray::class.java)
                        ?.filterIsInstance<ByteArray>()
                        ?.toTypedArray()
                        ?: emptyArray()
                } else {
                    @Suppress("DEPRECATION")
                    (bundle.get("pdus") as? Array<*>)?.filterIsInstance<ByteArray>()?.toTypedArray()
                        ?: emptyArray()
                }
            }

            private fun createSmsMessage(pdu: ByteArray, format: String?): SmsMessage? {
                return try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        SmsMessage.createFromPdu(pdu, format)
                    } else {
                        @Suppress("DEPRECATION")
                        SmsMessage.createFromPdu(pdu)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error creating SmsMessage from PDU", e)
                    null
                }
            }

            private fun processCustomSms(intent: Intent) {
                forwardSmsToFlutter(
                    sender = intent.getStringExtra("sender") ?: "unknown",
                    message = intent.getStringExtra("message") ?: "no content"
                )
            }
        }

        val filter = IntentFilter().apply {
            addAction("android.provider.Telephony.SMS_RECEIVED")
            addAction("sms-received")
            priority = 999 // High priority for SMS reception
        }
        
        try {
            registerReceiver(smsReceiver, filter)
            Log.d(TAG, "SMS receiver registered successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register SMS receiver", e)
        }
    }

    private fun forwardSmsToFlutter(sender: String, message: String) {
        Log.d(TAG, "Forwarding SMS to Flutter - Sender: $sender")
        eventSink?.success(
            mapOf(
                "sender" to sender,
                "message" to message,
                "timestamp" to System.currentTimeMillis()
            )
        ) ?: Log.w(TAG, "EventSink is null - message not delivered")
    }

    private fun unregisterSmsReceiver() {
        try {
            smsReceiver?.let {
                unregisterReceiver(it)
                smsReceiver = null
                Log.d(TAG, "SMS receiver unregistered successfully")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to unregister SMS receiver", e)
        }
    }

    private fun requestSmsPermissions(result: MethodChannel.Result) {
        val permissions = arrayOf(
            Manifest.permission.RECEIVE_SMS,
            Manifest.permission.READ_SMS,
            Manifest.permission.SEND_SMS
        )

        if (hasSmsPermissions()) {
            result.success(true)
            return
        }

        ActivityCompat.requestPermissions(this, permissions, SMS_PERMISSION_CODE)
        // Note: Flutter side should listen for onRequestPermissionsResult
    }

    private fun hasSmsPermissions(): Boolean {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED &&
                ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED &&
                ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED
    }
    
    private fun sendFileViaIntent(filePath: String, recipients: List<String>, message: String): Boolean {
        try {
            val file = File(filePath)
            if (!file.exists()) return false
            
            val uri = FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.provider",
                file
            )
            
            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                type = "video/*"
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_TEXT, message)
                putExtra("address", recipients.joinToString(";"))
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            
            val shareIntent = Intent.createChooser(sendIntent, null)
            startActivity(shareIntent)
            
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Error sending file", e)
            return false
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterSmsReceiver()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        
        if (requestCode == SMS_PERMISSION_CODE) {
            Log.d(TAG, "SMS permission request completed")
            // You can add additional handling here if needed
        }
    }
}
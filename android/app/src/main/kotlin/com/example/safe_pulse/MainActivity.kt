package com.example.safe_pulse

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val SMS_CHANNEL = "sms_receiver"
    private val SMS_EVENT_CHANNEL = "sms_receiver/events"
    private val SMS_PERMISSION_CODE = 101
    private var smsReceiver: BroadcastReceiver? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Method Channel for permission requests
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestSmsPermissions" -> requestSmsPermissions(result)
                "hasSmsPermissions" -> result.success(hasSmsPermissions())
                else -> result.notImplemented()
            }
        }

        // Event Channel for receiving SMS
        EventChannel(flutterEngine.dartExecutor, SMS_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    eventSink = events
                    setupSmsReceiver()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    unregisterSmsReceiver()
                }
            }
        )
    }

    private fun setupSmsReceiver() {
        smsReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val sender = intent.getStringExtra("sender")
                val message = intent.getStringExtra("message")
                val timestamp = intent.getLongExtra("timestamp", 0L)

                eventSink?.success(mapOf(
                    "sender" to sender,
                    "message" to message,
                    "timestamp" to timestamp
                ))
            }
        }

        registerReceiver(smsReceiver, IntentFilter("android.provider.Telephony.SMS_RECEIVED"))
    }

    private fun unregisterSmsReceiver() {
        smsReceiver?.let {
            unregisterReceiver(it)
            smsReceiver = null
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
        // The permission result will be handled in onRequestPermissionsResult
        // Flutter side should listen for the actual permission status changes
    }

    private fun hasSmsPermissions(): Boolean {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED &&
                ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED &&
                ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED
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
            // You can add logic here to notify Flutter about permission changes
            // For example through another method channel call
        }
    }
}
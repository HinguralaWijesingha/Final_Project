package com.example.safe_pulse

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class LockScreenReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            "com.example.safe_pulse.EMERGENCY_ACTION" -> {
                // Initialize Flutter engine and send alert
                val flutterEngine = FlutterEngine(context.applicationContext)
                flutterEngine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint.createDefault()
                )
                
                MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "safepulse/emergency")
                    .invokeMethod("sendEmergencyAlert", null)
                
                // Start MainActivity to handle screen wake-up
                val activityIntent = Intent(context, MainActivity::class.java).apply {
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                    )
                }
                context.startActivity(activityIntent)
                
                context.stopService(Intent(context, EmergencyForegroundService::class.java))
            }
            
            Intent.ACTION_SCREEN_OFF -> {
                val serviceIntent = Intent(context, EmergencyForegroundService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            }
        }
    }
}
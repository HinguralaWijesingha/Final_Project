package com.example.safe_pulse

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class EmergencyForegroundService : Service() {
    private lateinit var wakeLock: PowerManager.WakeLock
    
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK or 
            PowerManager.ON_AFTER_RELEASE,
            "SafePulse::EmergencyWakeLock"
        ).apply {
            setReferenceCounted(false)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = createEmergencyNotification()
        startForeground(1, notification)
        
        if (!wakeLock.isHeld) {
            wakeLock.acquire(10 * 60 * 1000L /*10 minutes*/)
        }
        
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null 
    }

    override fun onDestroy() {
        if (wakeLock.isHeld) {
            wakeLock.release()
        }
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "emergency_service_channel",
                "Emergency Service",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Keeps emergency mode active"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setShowBadge(true)
                setBypassDnd(true) 
            }
            
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun createEmergencyNotification(): Notification {
        // Create  emergency alert
        val emergencyIntent = Intent(this, LockScreenReceiver::class.java).apply {
            action = "com.example.safe_pulse.EMERGENCY_ACTION"
        }
        
        val emergencyPendingIntent = PendingIntent.getBroadcast(
            this,
            0,
            emergencyIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Create  fake call
        val fakeCallIntent = Intent(this, LockScreenReceiver::class.java).apply {
            action = "com.example.safe_pulse.FAKE_CALL_ACTION"
        }
        
        val fakeCallPendingIntent = PendingIntent.getBroadcast(
            this,
            1,
            fakeCallIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, "emergency_service_channel")
            .setContentTitle("Emergency Mode Active")
            .setContentText("Tap to send emergency alert or make fake call")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setShowWhen(false)
            .setContentIntent(emergencyPendingIntent) 
            .addAction(
                NotificationCompat.Action.Builder(
                    android.R.drawable.ic_dialog_alert,
                    "SEND ALERT",
                    emergencyPendingIntent
                ).build()
            )
            .addAction(
                NotificationCompat.Action.Builder(
                    android.R.drawable.ic_menu_call,
                    "CALL",
                    fakeCallPendingIntent
                ).build()
            )
            .build()
    }
}
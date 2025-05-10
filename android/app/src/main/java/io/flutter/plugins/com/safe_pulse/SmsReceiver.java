package io.flutter.plugins.com.example.safe_pulse;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.os.IBinder;
import android.telephony.SmsMessage;
import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;
import io.flutter.embedding.android.FlutterActivity;

public class SmsReceiver extends BroadcastReceiver {
    private static final String SMS_RECEIVED_ACTION = "sms-received";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent.getAction() != null && intent.getAction().equals("android.provider.Telephony.SMS_RECEIVED")) {
            Bundle bundle = intent.getExtras();
            if (bundle != null) {
                try {
                    Object[] pdus = (Object[]) bundle.get("pdus");
                    if (pdus != null) {
                        for (Object pdu : pdus) {
                            SmsMessage message;
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                String format = bundle.getString("format");
                                message = SmsMessage.createFromPdu((byte[]) pdu, format);
                            } else {
                                message = SmsMessage.createFromPdu((byte[]) pdu);
                            }

                            String sender = message.getOriginatingAddress();
                            String body = message.getMessageBody();

                            // Broadcast to Flutter
                            Intent localIntent = new Intent(SMS_RECEIVED_ACTION);
                            localIntent.putExtra("sender", sender);
                            localIntent.putExtra("message", body);
                            context.sendBroadcast(localIntent);

                            // Start the SMS service
                            Intent serviceIntent = new Intent(context, SmsService.class);
                            serviceIntent.putExtra("sender", sender);
                            serviceIntent.putExtra("message", body);
                            
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                context.startForegroundService(serviceIntent);
                            } else {
                                context.startService(serviceIntent);
                            }
                        }
                    }
                } catch (Exception e) {
                    e.printStackTrace();
                }
            }
        }
    }

    public static class SmsService extends Service {
        private static final String CHANNEL_ID = "SmsServiceChannel";
        private static final int NOTIFICATION_ID = 123;

        @Override
        public void onCreate() {
            super.onCreate();
            createNotificationChannel();
        }

        @Override
        public int onStartCommand(Intent intent, int flags, int startId) {
            String sender = intent.getStringExtra("sender");
            String message = intent.getStringExtra("message");

            // Create notification
            Intent notificationIntent = new Intent(this, FlutterActivity.class);
            notificationIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
            PendingIntent pendingIntent = PendingIntent.getActivity(
                this,
                0,
                notificationIntent,
                PendingIntent.FLAG_IMMUTABLE
            );

            Notification notification = new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("New SMS from " + sender)
                .setContentText(message)
                .setSmallIcon(android.R.drawable.ic_dialog_email) // Replace with your own icon
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .build();

            startForeground(NOTIFICATION_ID, notification);

            return START_NOT_STICKY;
        }

        private void createNotificationChannel() {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                NotificationChannel serviceChannel = new NotificationChannel(
                    CHANNEL_ID,
                    "SMS Service Channel",
                    NotificationManager.IMPORTANCE_DEFAULT
                );
                NotificationManager manager = getSystemService(NotificationManager.class);
                manager.createNotificationChannel(serviceChannel);
            }
        }

        @Nullable
        @Override
        public IBinder onBind(Intent intent) {
            return null;
        }
    }
}
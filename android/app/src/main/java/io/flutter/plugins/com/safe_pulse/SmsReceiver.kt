package io.flutter.plugins.com.safe_pulse

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.telephony.SmsMessage
import android.util.Log

class SmsReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "SMS_RECEIVER"
        private const val SMS_RECEIVED_ACTION = "android.provider.Telephony.SMS_RECEIVED"
        private const val FLUTTER_ACTION = "sms-received"
        private const val PDU_TYPE = "pdus"
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "SMS intent received with action: ${intent.action}")
        
        if (intent.action == SMS_RECEIVED_ACTION) {
            val bundle = intent.extras ?: run {
                Log.w(TAG, "No extras found in SMS intent")
                return
            }
            processSmsIntent(context, bundle)
        }
    }

    private fun processSmsIntent(context: Context, bundle: Bundle) {
        try {
            val pdus = getPdusFromBundle(bundle)
            if (pdus.isEmpty()) {
                Log.w(TAG, "No PDUs found in bundle")
                return
            }

            val messages = parseMessagesFromPdus(bundle, pdus)
            messages.forEach { message ->
                processSingleMessage(context, message)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing SMS", e)
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun getPdusFromBundle(bundle: Bundle): Array<ByteArray> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            bundle.getParcelableArray(PDU_TYPE, ByteArray::class.java)?.let {
                Array(it.size) { i -> it[i] as ByteArray }
            } ?: emptyArray()
        } else {
            @Suppress("DEPRECATION")
            (bundle.get(PDU_TYPE) as? Array<*>)?.filterIsInstance<ByteArray>()?.toTypedArray()
                ?: emptyArray()
        }
    }

    private fun parseMessagesFromPdus(bundle: Bundle, pdus: Array<ByteArray>): List<SmsMessage> {
        return pdus.mapNotNull { pdu ->
            try {
                val format = bundle.getString("format")
                SmsMessage.createFromPdu(pdu, format)
            } catch (e: Exception) {
                Log.e(TAG, "Error creating SmsMessage from PDU", e)
                null
            }
        }
    }

    private fun processSingleMessage(context: Context, message: SmsMessage) {
        val sender = message.originatingAddress ?: "unknown"
        val body = message.messageBody ?: "no content"
        
        Log.d(TAG, "Processing SMS from $sender: ${body.take(30)}...")

        forwardToMainActivity(context, sender, body)
    }

    private fun forwardToMainActivity(context: Context, sender: String, body: String) {
        try {
            val intent = Intent().apply {
                setClassName(context, "io.flutter.plugins.com.safe_pulse.MainActivity")
                action = FLUTTER_ACTION
                putExtra("sender", sender)
                putExtra("message", body)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            context.startActivity(intent)
            Log.d(TAG, "SMS forwarded to MainActivity")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to forward SMS to MainActivity", e)
        }
    }
}
package com.example.no_mercy_alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONObject

object AlarmRescheduler {
    fun rescheduleAll(context: Context) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        // Find keys: alarm_<id> where value is JSON string
        val all = prefs.all
        for ((key, value) in all) {
            if (!key.startsWith("alarm_")) continue
            // Exclude "alarm_<id>_first_wrong_at_ms"
            if (key.endsWith("_first_wrong_at_ms")) continue

            val idStr = key.removePrefix("alarm_")
            val alarmId = idStr.toIntOrNull() ?: continue
            val json = value as? String ?: continue

            val triggerAtMillis = extractTimeMillis(json) ?: continue

            // If it's already overdue, enqueue and ring immediately (meets your "12 hours late still rings")
            val now = System.currentTimeMillis()
            if (triggerAtMillis <= now) {
                RingQueue.enqueue(context, alarmId)
                RingQueue.startRingingServiceIfNeeded(context)
                continue
            }

            val intent = Intent(context, AlarmReceiver::class.java).apply {
                putExtra(AlarmReceiver.EXTRA_ALARM_ID, alarmId)
                putExtra(AlarmReceiver.EXTRA_TRIGGER_AT_MILLIS, triggerAtMillis)
            }

            val pi = PendingIntent.getBroadcast(
                context,
                alarmId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutableFlag()
            )

            am.cancel(pi)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
            } else {
                am.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
            }
        }
    }


    private fun extractTimeMillis(json: String): Long? {
        return try {
            val obj = JSONObject(json)
            obj.optLong("timeMillis", -1L).takeIf { it > 0 }
        } catch (_: Throwable) {
            null
        }
    }


    private fun pendingIntentImmutableFlag(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
    }
    
}
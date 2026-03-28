package com.example.no_mercy_alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.content.ContextCompat

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val alarmId = intent.getIntExtra(EXTRA_ALARM_ID, -1)
        if (alarmId == -1) return

        val scheduledAtMillis = intent.getLongExtra(EXTRA_TRIGGER_AT_MILLIS, -1L)
        val firedAtMillis = System.currentTimeMillis()

        // Always append into ring-buffer (overwrites after 20)
        AlarmRingLog.appendFired(
            context = context,
            alarmId = alarmId,
            scheduledAtMillis = if (scheduledAtMillis > 0) scheduledAtMillis else firedAtMillis,
            firedAtMillis = firedAtMillis,
            state = "FIRED",
        )

        // Start foreground service for audio
        val serviceIntent = Intent(context, RingingService::class.java).apply {
            putExtra(EXTRA_ALARM_ID, alarmId)
            putExtra(EXTRA_FROM_ALARM, true)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ContextCompat.startForegroundService(context, serviceIntent)
        } else {
            context.startService(serviceIntent)
        }

        // Best-effort: try to bring UI; may be blocked by background restrictions.
        val activityIntent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(EXTRA_ALARM_ID, alarmId)
            putExtra(EXTRA_FROM_ALARM, true)
        }
        try {
            context.startActivity(activityIntent)
        } catch (_: Throwable) {
            // Notification OPEN action should still allow user to bring app to front.
        }
    }

    companion object {
        const val EXTRA_ALARM_ID = "alarm_id"
        const val EXTRA_FROM_ALARM = "from_alarm"
        const val EXTRA_TRIGGER_AT_MILLIS = "trigger_at_millis"
    }
}
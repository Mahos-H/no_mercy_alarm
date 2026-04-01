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

        AlarmRingLog.appendFired(
            context = context,
            alarmId = alarmId,
            scheduledAtMillis = if (scheduledAtMillis > 0) scheduledAtMillis else firedAtMillis,
            firedAtMillis = firedAtMillis,
            state = "FIRED",
        )

        // Enqueue (persistently) so alarms are never dropped
        RingQueue.enqueue(context, alarmId)

        // Start/continue ringing based on queue
        RingQueue.startRingingServiceIfNeeded(context)

        // Best-effort bring UI for *current active* alarm
        val active = RingQueue.getActiveAlarmId(context) ?: alarmId
        val activityIntent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(EXTRA_ALARM_ID, active)
            putExtra(EXTRA_FROM_ALARM, true)
        }
        try { context.startActivity(activityIntent) } catch (_: Throwable) {}
    }

    companion object {
        const val EXTRA_ALARM_ID = "alarm_id"
        const val EXTRA_FROM_ALARM = "from_alarm"
        const val EXTRA_TRIGGER_AT_MILLIS = "trigger_at_millis"
    }
}
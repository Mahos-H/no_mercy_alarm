package com.example.no_mercy_alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class StopAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val alarmId = intent?.getIntExtra(AlarmReceiver.EXTRA_ALARM_ID, -1) ?: -1

        // Stop audio
        context.stopService(Intent(context, RingingService::class.java))

        // Clear/advance queue so it doesn't get stuck
        if (alarmId > 0) {
            RingQueue.stopAndAdvance(context, alarmId)
        } else {
            // Fallback: if missing alarmId, clear everything (optional)
            RingQueue.clear(context)
        }

        // Optional: cancel the foreground notification id (99901)
        // (Only works if you also post/cancel via NotificationManager)
    }
}
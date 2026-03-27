package com.example.no_mercy_alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class StopAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        // Stop service
        context.stopService(Intent(context, RingingService::class.java))

        // Clear ringing state
        val prefs = context.getSharedPreferences(AlarmReceiver.PREFS_NAME, Context.MODE_PRIVATE)
        val activeId = prefs.getInt(AlarmReceiver.KEY_ACTIVE_ALARM_ID, -1)

        prefs.edit()
            .putBoolean(AlarmReceiver.KEY_RINGING, false)
            .remove(AlarmReceiver.KEY_ACTIVE_ALARM_ID)
            .remove("alarm_${activeId}_first_wrong_at_ms")
            .apply()
    }
}
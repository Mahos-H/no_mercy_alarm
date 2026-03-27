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

        // Mark ringing + active id in SharedPreferences
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val alreadyRinging = prefs.getBoolean(KEY_RINGING, false)
        if (alreadyRinging) {
            // Only one active at a time: ignore new triggers
            return
        }

        prefs.edit()
            .putBoolean(KEY_RINGING, true)
            .putInt(KEY_ACTIVE_ALARM_ID, alarmId)
            .apply()

        // Start foreground service for audio
        val serviceIntent = Intent(context, RingingService::class.java).apply {
            putExtra(EXTRA_ALARM_ID, alarmId)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ContextCompat.startForegroundService(context, serviceIntent)
        } else {
            context.startService(serviceIntent)
        }

        // Launch the app UI full-screen immediately
        val activityIntent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(EXTRA_ALARM_ID, alarmId)
            putExtra(EXTRA_FROM_ALARM, true)
        }
        context.startActivity(activityIntent)
    }

    companion object {
        const val EXTRA_ALARM_ID = "alarm_id"
        const val EXTRA_FROM_ALARM = "from_alarm"

        const val PREFS_NAME = "no_mercy_alarm_prefs"
        const val KEY_RINGING = "alarm_ringing"
        const val KEY_ACTIVE_ALARM_ID = "active_alarm_id"
    }
}
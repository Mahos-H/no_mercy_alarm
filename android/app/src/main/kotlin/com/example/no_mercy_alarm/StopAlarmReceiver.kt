package com.example.no_mercy_alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class StopAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        // Stop service
        context.stopService(Intent(context, RingingService::class.java))

        // Clear ringing state
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        val activeId: Int = try {
            prefs.getInt("flutter.active_alarm_id", -1)
        } catch (_: ClassCastException) {
            val raw = prefs.getString("flutter.active_alarm_id", null)
            raw?.removePrefix("i:")?.toIntOrNull() ?: -1
        }

        prefs.edit()
            .putBoolean("flutter.alarm_ringing", false)
            .remove("flutter.active_alarm_id")
            .remove("flutter.alarm_${activeId}_first_wrong_at_ms")
            .apply()
    }
}
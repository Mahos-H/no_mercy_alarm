package com.example.no_mercy_alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class StopAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        // Emergency stop: stop audio service
        context.stopService(Intent(context, RingingService::class.java))
        // Do not mutate FlutterSharedPreferences here (avoids key mismatch surprises).
    }
}
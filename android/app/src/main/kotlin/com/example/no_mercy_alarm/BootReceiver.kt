package com.example.no_mercy_alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        // We can't easily reschedule all alarms here without storing trigger time separately
        // and iterating them; simplest approach: let Flutter reschedule on next app open.
        // If you want full reschedule here, we can implement it by storing alarm times in prefs
        // and scheduling PendingIntents again.

        // No-op for now (prevents crashes / placeholder).
    }
}
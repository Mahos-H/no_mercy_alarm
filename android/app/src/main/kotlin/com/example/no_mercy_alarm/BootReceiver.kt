package com.example.no_mercy_alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        // Reschedule alarms after reboot + ring overdue alarms via queue
        AlarmRescheduler.rescheduleAll(context)
    }
}
package com.example.no_mercy_alarm

import android.content.Context
import android.content.Intent
import org.json.JSONArray
import android.os.Build
import androidx.core.content.ContextCompat

object RingQueue {
    private const val PREFS = "alarm_ring_queue"
    private const val KEY_QUEUE = "queue" // JSON array of ints
    private const val KEY_ACTIVE = "active_alarm_id"

    private val lock = Any()

    fun enqueue(context: Context, alarmId: Int) {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val arr = JSONArray(prefs.getString(KEY_QUEUE, "[]"))
            // avoid duplicates
            for (i in 0 until arr.length()) {
                if (arr.optInt(i) == alarmId) return
            }
            arr.put(alarmId)
            prefs.edit().putString(KEY_QUEUE, arr.toString()).commit()
        }
    }

    fun getActiveAlarmId(context: Context): Int? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val v = prefs.getInt(KEY_ACTIVE, -1)
        return if (v > 0) v else null
    }

    fun ensureActiveFromQueue(context: Context): Int? {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val active = prefs.getInt(KEY_ACTIVE, -1)
            if (active > 0) return active

            val arr = JSONArray(prefs.getString(KEY_QUEUE, "[]"))
            if (arr.length() == 0) return null

            val next = arr.optInt(0, -1)
            if (next <= 0) return null

            prefs.edit().putInt(KEY_ACTIVE, next).commit()
            return next
        }
    }

    fun stopAndAdvance(context: Context, alarmId: Int) {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

            // Remove from queue wherever it is
            val arr = JSONArray(prefs.getString(KEY_QUEUE, "[]"))
            val newArr = JSONArray()
            for (i in 0 until arr.length()) {
                val v = arr.optInt(i)
                if (v != alarmId) newArr.put(v)
            }

            // Clear active if it matches
            val active = prefs.getInt(KEY_ACTIVE, -1)
            val editor = prefs.edit()
                .putString(KEY_QUEUE, newArr.toString())
            if (active == alarmId) editor.putInt(KEY_ACTIVE, -1)
            editor.commit()
        }

        // Start next alarm if any
        startRingingServiceIfNeeded(context)
    }

    fun clear(context: Context) {
        synchronized(lock) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().clear().commit()
        }
    }

    fun startRingingServiceIfNeeded(context: Context) {
        val next = ensureActiveFromQueue(context) ?: run {
            // no more alarms, stop service
            context.stopService(Intent(context, RingingService::class.java))
            return
        }

        // Ensure service is running for the active alarm
        val serviceIntent = Intent(context, RingingService::class.java).apply {
            putExtra(AlarmReceiver.EXTRA_ALARM_ID, next)
            putExtra(AlarmReceiver.EXTRA_FROM_ALARM, true)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ContextCompat.startForegroundService(context, serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
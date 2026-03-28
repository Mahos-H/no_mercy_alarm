package com.example.no_mercy_alarm

import android.content.Context
import org.json.JSONObject

/**
 * Ring-buffer log: 20 slots (1..20). lastRungIdx = 0 means none yet.
 * Thread-safe via a single lock and commit() for atomicity in receivers.
 */
object AlarmRingLog {
    private const val PREFS_NAME = "alarm_ring_log"
    private const val KEY_LAST_RUNG_IDX = "last_rung_idx"
    private const val SLOT_PREFIX = "slot_" // slot_1..slot_20
    private const val MAX_SLOTS = 20

    private val lock = Any()

    data class Event(
        val idx: Int,
        val alarmId: Int,
        val scheduledAtMillis: Long,
        val firedAtMillis: Long,
        val state: String,
        val reason: String? = null,
    ) {
        fun toJsonString(): String {
            val o = JSONObject()
            o.put("idx", idx)
            o.put("alarmId", alarmId)
            o.put("scheduledAtMillis", scheduledAtMillis)
            o.put("firedAtMillis", firedAtMillis)
            o.put("state", state)
            if (reason != null) o.put("reason", reason)
            return o.toString()
        }
    }

    fun getLastRungIdx(context: Context): Int {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getInt(KEY_LAST_RUNG_IDX, 0)
    }

    fun getSlot(context: Context, idx: Int): String? {
        if (idx !in 1..MAX_SLOTS) return null
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString("$SLOT_PREFIX$idx", null)
    }

    fun getLastEvent(context: Context): String? {
        val last = getLastRungIdx(context)
        if (last == 0) return null
        return getSlot(context, last)
    }

    /**
     * Append a FIRED event into the ring buffer and update last_rung_idx.
     * Returns the idx used (1..20).
     */
    fun appendFired(
        context: Context,
        alarmId: Int,
        scheduledAtMillis: Long,
        firedAtMillis: Long,
        state: String = "FIRED",
        reason: String? = null,
    ): Int {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val last = prefs.getInt(KEY_LAST_RUNG_IDX, 0)
            val next = (last % MAX_SLOTS) + 1 // 0->1, 1->2, ... 20->1

            val event = Event(
                idx = next,
                alarmId = alarmId,
                scheduledAtMillis = scheduledAtMillis,
                firedAtMillis = firedAtMillis,
                state = state,
                reason = reason,
            )

            // commit() to make sure receiver doesn't die before persisting
            prefs.edit()
                .putString("$SLOT_PREFIX$next", event.toJsonString())
                .putInt(KEY_LAST_RUNG_IDX, next)
                .commit()

            return next
        }
    }

    /**
     * Optional helper if you want to mark STOPPED in the log.
     * Not required for routing, but useful for debugging.
     */
    fun markStopped(context: Context, idx: Int) {
        if (idx !in 1..MAX_SLOTS) return
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val raw = prefs.getString("$SLOT_PREFIX$idx", null) ?: return
            val obj = try { JSONObject(raw) } catch (_: Throwable) { return }
            obj.put("state", "STOPPED")
            prefs.edit().putString("$SLOT_PREFIX$idx", obj.toString()).commit()
        }
    }

    fun clear(context: Context) {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().clear().commit()
        }
    }
}
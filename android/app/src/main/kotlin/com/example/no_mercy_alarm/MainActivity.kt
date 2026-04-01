package com.example.no_mercy_alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "no_mercy_alarm/alarm"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scheduleExactAlarm" -> {
                        val alarmId = call.argument<Int>("alarmId")
                        val triggerAtMillis = call.argument<Long>("triggerAtMillis")
                        if (alarmId == null || triggerAtMillis == null) {
                            result.error("BAD_ARGS", "alarmId/triggerAtMillis required", null)
                            return@setMethodCallHandler
                        }

                        scheduleExactAlarm(this, alarmId, triggerAtMillis)
                        result.success(true)
                    }

                    "cancelExactAlarm" -> {
                        val alarmId = call.argument<Int>("alarmId")
                        if (alarmId == null) {
                            result.error("BAD_ARGS", "alarmId required", null)
                            return@setMethodCallHandler
                        }
                        cancelExactAlarm(this, alarmId)
                        result.success(true)
                    }

                    "stopRingingService" -> {
                        stopService(Intent(this, RingingService::class.java))
                        result.success(true)
                    }

                    // ===== Ring log API =====
                    "ringLog_getLastEvent" -> {
                        result.success(AlarmRingLog.getLastEvent(this))
                    }

                    "ringLog_getLastRungIdx" -> {
                        result.success(AlarmRingLog.getLastRungIdx(this))
                    }

                    "ringLog_getSlot" -> {
                        val idx = call.argument<Int>("idx")
                        if (idx == null) {
                            result.error("BAD_ARGS", "idx required", null)
                            return@setMethodCallHandler
                        }
                        result.success(AlarmRingLog.getSlot(this, idx))
                    }

                    "ringQueue_getActiveAlarmId" -> {
                        result.success(RingQueue.getActiveAlarmId(this))
                    }

                    "ringQueue_clear" -> {
                        RingQueue.clear(this)
                        result.success(true)
                    }

                    "stopAndAdvanceQueue" -> {
                        val alarmId = call.argument<Int>("alarmId")
                        if (alarmId == null) {
                            result.error("BAD_ARGS", "alarmId required", null)
                            return@setMethodCallHandler
                        }
                        // stop sound first
                        stopService(Intent(this, RingingService::class.java))
                        // advance queue
                        RingQueue.stopAndAdvance(this, alarmId)
                        result.success(true)
                    }

                    else -> result.notImplemented()
                
                }
            }
    }

    private fun scheduleExactAlarm(context: Context, alarmId: Int, triggerAtMillis: Long) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra(AlarmReceiver.EXTRA_ALARM_ID, alarmId)
            putExtra(AlarmReceiver.EXTRA_TRIGGER_AT_MILLIS, triggerAtMillis)
        }

        val pi = PendingIntent.getBroadcast(
            context,
            alarmId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutableFlag()
        )

        // Cancel any existing one with same id
        am.cancel(pi)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
        } else {
            am.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
        }
    }

    private fun cancelExactAlarm(context: Context, alarmId: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java)

        val pi = PendingIntent.getBroadcast(
            context,
            alarmId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutableFlag()
        )

        am.cancel(pi)
    }

    private fun pendingIntentImmutableFlag(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
    }
}
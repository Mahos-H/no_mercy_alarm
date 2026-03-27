package com.example.no_mercy_alarm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.example.no_mercy_alarm.R
import java.io.File

class RingingService : Service() {

    private var player: MediaPlayer? = null
    private var alarmId: Int = -1

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        alarmId = intent?.getIntExtra(AlarmReceiver.EXTRA_ALARM_ID, -1) ?: -1

        startForeground(NOTIF_ID, buildNotification())
        startAudioForAlarm(alarmId)

        return START_STICKY
    }

    private fun startAudioForAlarm(alarmId: Int) {
        stopAudio()

        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val alarmJson = prefs.getString("alarm_$alarmId", null)
        val customPath = extractSoundPath(alarmJson)

        try {
            val mp = MediaPlayer()
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )

            if (customPath != null && File(customPath).exists()) {
                mp.setDataSource(customPath)
                mp.isLooping = true
                mp.prepare()
            } else {
                val afd = resources.openRawResourceFd(R.raw.alarm_sound)
                mp.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                afd.close()
                mp.isLooping = true
                mp.prepare()
            }

            mp.setVolume(1.0f, 1.0f)
            mp.start()
            player = mp
        } catch (_: Throwable) {
            // Keep service alive even if playback fails
        }
    }

    private fun extractSoundPath(json: String?): String? {
        if (json == null) return null
        val key = "\"soundPath\":"
        val idx = json.indexOf(key)
        if (idx == -1) return null
        val after = json.substring(idx + key.length).trim()
        if (after.startsWith("null")) return null

        val firstQuote = after.indexOf('\"')
        if (firstQuote == -1) return null
        val secondQuote = after.indexOf('\"', firstQuote + 1)
        if (secondQuote == -1) return null

        return after.substring(firstQuote + 1, secondQuote)
    }

    private fun stopAudio() {
        try { player?.stop() } catch (_: Throwable) {}
        try { player?.release() } catch (_: Throwable) {}
        player = null
    }

    override fun onDestroy() {
        stopAudio()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            val ch = NotificationChannel(
                CHANNEL_ID,
                "Alarm Ringing",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Foreground service for alarm ringing"
                setSound(null, null)
                enableVibration(true)
            }
            nm.createNotificationChannel(ch)
        }
    }

    private fun buildNotification(): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(AlarmReceiver.EXTRA_ALARM_ID, alarmId)
            putExtra(AlarmReceiver.EXTRA_FROM_ALARM, true)
        }

        val openPending = PendingIntent.getActivity(
            this,
            1,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
        )

        val stopIntent = Intent(this, StopAlarmReceiver::class.java)
        val stopPending = PendingIntent.getBroadcast(
            this,
            2,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("⏰ ALARM RINGING!")
            .setContentText("Open the app to enter password and stop it.")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(openPending)
            .addAction(0, "OPEN", openPending)
            .addAction(0, "EMERGENCY STOP", stopPending)
            .build()
    }

    private fun immutableFlag(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
    }

    companion object {
        private const val CHANNEL_ID = "ringing_service_channel"
        private const val NOTIF_ID = 99901
    }
}
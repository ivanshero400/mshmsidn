package fajr.din.hk

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.util.Log
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat

/**
 * Persistent foreground service — the same mechanism call/messaging apps use
 * to stay alive in the background. It pins an ongoing, lock-screen-visible
 * notification showing a live clock, the date, the current prayer and the
 * next prayer with a live countdown (TextClock/Chronometer tick by themselves,
 * so this costs zero battery between refreshes).
 *
 * Side benefit: while a foreground service is running the OS treats the app
 * as actively in use, so it is far less likely to kill it or defer its alarms.
 */
class PrayerInfoService : Service() {

    companion object {
        private const val TAG = "PrayerInfo"
        const val CHANNEL_ID = "prayer_info_channel"
        const val NOTIF_ID = 7100

        /** Start (or refresh the content of) the persistent notification. */
        fun start(context: Context) {
            try {
                val intent = Intent(context, PrayerInfoService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                // Background-start restrictions on some OEMs — alarms still work.
                Log.w(TAG, "could not start info service: ${e.message}")
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannel()
        startForeground(NOTIF_ID, buildNotification(this))
        // Self-heal: whenever the system (re)starts us, make sure the adhan
        // alarm chain is armed too.
        AlarmScheduler.rescheduleAll(this)
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // User swiped the app away: re-arm alarms and resurrect this service
        // in a moment via AlarmManager (survives process death).
        scheduleSelfRestart()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        scheduleSelfRestart()
        super.onDestroy()
    }

    private fun scheduleSelfRestart() {
        try {
            AlarmScheduler.rescheduleAll(this)
            val am = getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
            val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                PendingIntent.getForegroundService(
                    this, 7102, Intent(this, PrayerInfoService::class.java), piFlags,
                )
            } else {
                PendingIntent.getService(
                    this, 7102, Intent(this, PrayerInfoService::class.java), piFlags,
                )
            }
            am.setAndAllowWhileIdle(
                android.app.AlarmManager.RTC_WAKEUP,
                System.currentTimeMillis() + 2000L, pi,
            )
            Log.d(TAG, "self-restart armed")
        } catch (e: Exception) {
            Log.w(TAG, "self-restart failed: ${e.message}")
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID,
                    "شاشة مواقيت الصلاة",
                    NotificationManager.IMPORTANCE_LOW, // silent, no heads-up
                ).apply {
                    description = "إشعار دائم يعرض الصلاة الحالية والقادمة على شاشة القفل"
                    setShowBadge(false)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
                nm.createNotificationChannel(ch)
            }
        }
    }

    private fun buildNotification(context: Context): Notification {
        val prayers = PrayerStore.load(context)
        val (currentName, _) = PrayerStore.currentDisplay(prayers)
        val next = PrayerStore.next(prayers)

        val nextName = next?.first?.arabicName ?: "—"
        val nextTime = next?.first?.timeLabel ?: "--:--"

        val collapsed = RemoteViews(context.packageName, R.layout.notification_prayer)
        val expanded = RemoteViews(context.packageName, R.layout.notification_prayer_big)
        for (views in listOf(collapsed, expanded)) {
            views.setTextViewText(R.id.np_current, currentName)
            views.setTextViewText(R.id.np_next, "$nextName · $nextTime")
            if (next != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val base = SystemClock.elapsedRealtime() +
                    (next.second - System.currentTimeMillis())
                views.setChronometerCountDown(R.id.np_countdown, true)
                views.setChronometer(R.id.np_countdown, base, null, true)
            }
        }

        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val tapPi = PendingIntent.getActivity(
            context, 7101,
            Intent(context, MainActivity::class.java),
            piFlags,
        )

        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_mosque_white)
            .setContentTitle("الصلاة الحالية: $currentName")
            .setContentText("القادمة: $nextName في $nextTime")
            .setCustomContentView(collapsed)
            .setCustomBigContentView(expanded)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setContentIntent(tapPi)
            .setShowWhen(false)
            .build()
    }
}

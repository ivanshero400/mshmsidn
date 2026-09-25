package fajr.din.hk

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat

class AdhanAlarmReceiver : BroadcastReceiver() {
    companion object {
        const val CHANNEL_ID = "adhan_fullscreen"
        const val NOTIF_ID = 7001
    }

    override fun onReceive(context: Context, intent: Intent) {
        val prayerName = intent.getStringExtra("prayer_name") ?: "الصلاة"
        val soundKey = intent.getStringExtra("sound_key") ?: ""
        Log.d("AdhanAlarm", "Receiver FIRED! prayer=$prayerName sound=$soundKey")

        if (prayerName == AlarmScheduler.WAKE_AUTO_STOP_NAME) {
            AlarmScheduler.stopWakeAlarmAtSunrise(context)
            try { AlarmScheduler.rescheduleAll(context) } catch (_: Exception) {}
            return
        }

        if (AlarmScheduler.isWakeAlarmName(prayerName)) {
            AlarmScheduler.scheduleWakeAutoStopAtSunrise(context)
            showFullScreenAlarm(context, prayerName, soundKey)
            try { AlarmScheduler.rescheduleAll(context) } catch (_: Exception) {}
            return
        }

        // ── Lightweight alarm types (no full-screen takeover) ──
        when {
            prayerName.startsWith("PRE:") -> {
                val parts = prayerName.split(":")
                val name = PrayerStore.ARABIC_NAMES[parts.getOrNull(1)] ?: "الصلاة"
                val min = parts.getOrNull(2) ?: "15"
                plainNotification(
                    context, 7201,
                    "🕌 اقترب وقت صلاة $name",
                    "بقي $min دقيقة على الأذان — وقتٌ للوضوء والتهيؤ.",
                )
                return
            }
            prayerName.startsWith("END:") -> {
                val name = PrayerStore.ARABIC_NAMES[prayerName.removePrefix("END:")] ?: "الصلاة"
                plainNotification(
                    context, 7202,
                    "⏳ يوشك وقت $name على الخروج",
                    "بادر بأداء صلاة $name قبل خروج وقتها.",
                )
                return
            }

            prayerName.startsWith("ADHKAR_POST:") -> {
                val name = PrayerStore.ARABIC_NAMES[prayerName.removePrefix("ADHKAR_POST:")] ?: "الصلاة"
                plainNotification(
                    context, 7204,
                    "📿 أذكار بعد صلاة $name",
                    "أستغفر الله ×3… اضغط لقراءة أذكار ما بعد الصلاة من الكتاب والسنة.",
                    route = "/learn/adhkar",
                )
                return
            }
            prayerName == "ADHKAR_MORNING" -> {
                showFullScreenAdhkar(context, "morning", "☀️ أذكار الصباح")
                try { AlarmScheduler.rescheduleAll(context) } catch (_: Exception) {}
                return
            }
            prayerName == "ADHKAR_EVENING" -> {
                showFullScreenAdhkar(context, "evening", "🌅 أذكار المساء")
                try { AlarmScheduler.rescheduleAll(context) } catch (_: Exception) {}
                return
            }
            prayerName == "MULK_REMINDER" -> {
                showFullScreenAdhkar(context, "mulk", "🌙 سورة الملك قبل النوم")
                try { AlarmScheduler.rescheduleAll(context) } catch (_: Exception) {}
                return
            }
        }

        showFullScreenAlarm(context, prayerName, soundKey)

        // Self-perpetuate: re-arm the next occurrence of every prayer so the
        // chain never stops, even if the app is never opened again.
        try {
            AlarmScheduler.rescheduleAll(context)
        } catch (e: Exception) {
            Log.e("AdhanAlarm", "reschedule after fire failed: ${e.message}")
        }

        // A prayer boundary just passed: refresh the home-screen widget and
        // the lock-screen info notification with the new current/next prayer.
        try {
            Widgets.refreshAll(context)
            PrayerInfoService.start(context)
        } catch (e: Exception) {
            Log.e("AdhanAlarm", "widget/service refresh failed: ${e.message}")
        }
    }

    /**
     * Posts a high-importance full-screen-intent notification. This is the
     * Android-sanctioned way to surface a full-screen alarm from the
     * background / lock screen on Android 10+, where a bare startActivity()
     * from a receiver is blocked. A direct launch is also attempted as a
     * fast path for when the app is already in the foreground.
     */
    private fun showFullScreenAlarm(context: Context, prayerName: String, soundKey: String) {
        ensureChannel(context)
        val isWakeAlarm = AlarmScheduler.isWakeAlarmName(prayerName)
        val displayName = PrayerStore.ARABIC_NAMES[prayerName] ?: prayerName
        val wakeTitle = AlarmScheduler.wakeAlarmDisplayName(prayerName)

        val activityIntent = Intent(context, AdhanAlarmActivity::class.java).apply {
            putExtra("prayer_name", prayerName)
            putExtra("sound_key", soundKey)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
        }

        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val fullScreenPi = PendingIntent.getActivity(context, 1001, activityIntent, piFlags)

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_mosque_white)
            .setContentTitle(if (isWakeAlarm) wakeTitle else "🕌 حان وقت الصلاة")
            .setContentText(if (isWakeAlarm) "حان وقت الإيقاظ" else "دخل وقت صلاة $displayName")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setContentIntent(fullScreenPi)
            .setFullScreenIntent(fullScreenPi, true)
            .setTimeoutAfter(10 * 60 * 1000L)
            .build()

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID, notification)

        // Fast path: works when the app is visible or overlay permission is granted.
        try {
            context.startActivity(activityIntent)
        } catch (e: Exception) {
            Log.w("AdhanAlarm", "direct startActivity blocked (full-screen intent will handle it): ${e.message}")
        }
    }

    /**
     * Full-screen adhkar reveal (morning / evening / Surah al-Mulk). Mirrors
     * the adhan full-screen mechanism: a full-screen-intent notification that
     * opens AdhanAlarmActivity, which routes Flutter to "/adhkar-display".
     */
    private fun showFullScreenAdhkar(context: Context, type: String, title: String) {
        ensureChannel(context)

        val activityIntent = Intent(context, AdhanAlarmActivity::class.java).apply {
            putExtra("prayer_name", "ADHKAR")
            putExtra("adhkar_type", type)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
        }
        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val fullScreenPi = PendingIntent.getActivity(context, 1002, activityIntent, piFlags)

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_mosque_white)
            .setContentTitle(title)
            .setContentText("اضغط لعرض الأذكار")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setContentIntent(fullScreenPi)
            .setFullScreenIntent(fullScreenPi, true)
            .setTimeoutAfter(10 * 60 * 1000L)
            .build()

        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIF_ID, notification)

        try {
            context.startActivity(activityIntent)
        } catch (e: Exception) {
            Log.w("AdhanAlarm", "adhkar startActivity blocked (full-screen intent will handle): ${e.message}")
        }
    }

    /** Simple high-visibility notification; [route] deep-links into the app. */
    private fun plainNotification(
        context: Context, id: Int, title: String, body: String, route: String? = null,
    ) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            nm.getNotificationChannel("prayer_reminders") == null
        ) {
            nm.createNotificationChannel(
                NotificationChannel(
                    "prayer_reminders", "تذكيرات الصلاة",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply { description = "تذكير قبل الأذان وقبل خروج وقت الصلاة" },
            )
        }
        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val launch = Intent(context, MainActivity::class.java).apply {
            route?.let { putExtra("route", it) }
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val pi = PendingIntent.getActivity(context, id, launch, piFlags)
        val n = NotificationCompat.Builder(context, "prayer_reminders")
            .setSmallIcon(R.drawable.ic_mosque_white)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(id, n)
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "تنبيه الأذان",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "شاشة الأذان عند دخول وقت الصلاة"
                    setBypassDnd(true)
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                    enableVibration(true)
                }
                nm.createNotificationChannel(channel)
            }
        }
    }
}

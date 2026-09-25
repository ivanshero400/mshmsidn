package fajr.din.hk

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import java.util.Calendar

/**
 * Single source of truth for prayer alarms.
 *
 * Reads the prayer times that Flutter saved to SharedPreferences
 * (`flutter.prayer_times_json`) and arms an exact AlarmManager alarm for the
 * NEXT occurrence of each prayer. Because every alarm is (re)scheduled to the
 * next future occurrence, the chain perpetuates itself forever — even if the
 * Flutter app is never opened again. It is also re-armed after every device
 * reboot via [BootReceiver] and after every fire via [AdhanAlarmReceiver].
 */
object AlarmScheduler {
    private const val TAG = "AdhanAlarm"

    // Stable alarm IDs so re-arming overwrites the same pending intent.
    private val PRAYER_IDS = mapOf(
        "FAJR" to 1,
        "DHUHR" to 2,
        "ASR" to 3,
        "MAGHRIB" to 4,
        "ISHA" to 5,
    )
    /** Scheduled snooze re-fire. */
    const val SNOOZE_ID = 9200

    const val LEGACY_FAJR_ALARM_TEST_ID = 9601

    const val WAKE_FAJR_ID = 9701
    const val WAKE_ISHA_ID = 9702
    const val WAKE_AUTO_STOP_ID = 9703
    const val WAKE_RETURN_ID = 9704
    const val WAKE_FAJR_NAME = "FAJR_WAKE_ALARM"
    const val WAKE_ISHA_NAME = "ISHA_WAKE_ALARM"
    const val WAKE_AUTO_STOP_NAME = "WAKE_ALARM_AUTO_STOP"

    /** "Remind in 15 min" re-fire of an adhkar full-screen reveal. */
    const val ADHKAR_REMIND_ID = 9400

    private const val PRE_BASE_ID = 300 // pre-adhan reminders: 300 + prayer id
    private const val END_BASE_ID = 400 // end-of-window warnings: 400 + prayer id

    fun isWakeAlarmName(name: String): Boolean {
        return name == WAKE_FAJR_NAME || name == WAKE_ISHA_NAME
    }

    fun wakeAlarmDisplayName(name: String): String {
        return when (name) {
            WAKE_ISHA_NAME -> "منبه العشاء"
            else -> "منبه الفجر"
        }
    }

    /**
     * Read saved prayer times and (re)arm an exact alarm for the next
     * occurrence of each prayer. Idempotent — safe to call any number of times.
     */
    fun rescheduleAll(context: Context) {
        val prayers = PrayerStore.load(context)
        if (prayers.isEmpty()) {
            Log.w(TAG, "rescheduleAll: no saved prayer times yet")
            return
        }
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        // Prayers the user muted in the UI (plain CSV like "FAJR,ISHA").
        val muted = (prefs.getString("flutter.muted_prayers_csv", "") ?: "")
            .split(",").map { it.trim() }.filter { it.isNotEmpty() }.toSet()
        val wakeConfig = WakeAlarmConfig.fromPrefs(prefs)
        cancel(context, LEGACY_FAJR_ALARM_TEST_ID)

        var fajrTrigger: Long = 0
        var asrTrigger: Long = 0
        var ishaTrigger: Long = 0
        for (prayer in prayers) {
            val id = PRAYER_IDS[prayer.name] ?: continue
            if (wakeConfig.controls(prayer.name)) {
                cancel(context, id)
                continue
            }
            if (prayer.name in muted) {
                // Muted: make sure no stale alarm remains armed for it.
                cancel(context, id)
                continue
            }
            val trigger = nextOccurrence(prayer)
            scheduleExact(context, id, trigger, prayer.name, "")
            when (prayer.name) {
                "FAJR" -> fajrTrigger = trigger
                "ASR" -> asrTrigger = trigger
                "ISHA" -> ishaTrigger = trigger
            }
        }
        scheduleWakeAlarms(context, wakeConfig)

        // ── Pre-adhan reminders (wudu / walk-to-mosque time) ──
        val preMin = prefs.getLong("flutter.pre_adhan_min", 0L)
        if (preMin > 0) {
            for (prayer in prayers) {
                val id = PRAYER_IDS[prayer.name] ?: continue
                val t = nextOccurrence(prayer) - preMin * 60_000L
                if (t > System.currentTimeMillis() + 5000L) {
                    scheduleExact(context, PRE_BASE_ID + id, t, "PRE:${prayer.name}:$preMin", "")
                }
            }
        }

        // ── End-of-window warnings: N minutes before the prayer's time runs out.
        //    A prayer's window closes at the next prayer; Fajr closes at sunrise. ──
        val endMin = kotlin.runCatching {
            prefs.getLong("flutter.end_warning_min", 0L).toInt()
        }.getOrDefault(0)
        if (endMin > 0) {
            val withSunrise = PrayerStore.load(context, includeSunrise = true)
            for (i in withSunrise.indices) {
                val p = withSunrise[i]
                if (p.name == "SUNRISE") continue
                val next = withSunrise[(i + 1) % withSunrise.size]
                var endT = nextOccurrence(next)
                var startT = nextOccurrence(p)
                if (endT < startT) endT += 24 * 60 * 60 * 1000L // wraps past midnight
                val warnT = endT - endMin * 60_000L
                if (warnT > System.currentTimeMillis() + 5000L && warnT > startT) {
                    val id = PRAYER_IDS[p.name] ?: 9
                    scheduleExact(context, END_BASE_ID + id, warnT, "END:${p.name}", "")
                }
            }
        }

        // ── Adhkar notifications (opt-in from the Learn section) ──
        if (prefs.getBoolean("flutter.adhkar_notif", false)) {
            // Post-prayer adhkar ~18 min after each adhan
            for (prayer in prayers) {
                val id = PRAYER_IDS[prayer.name] ?: continue
                scheduleExact(
                    context, 500 + id,
                    nextOccurrence(prayer) + 18 * 60_000L,
                    "ADHKAR_POST:${prayer.name}", "",
                )
            }
            // Morning adhkar after Fajr, evening after Asr (their sunnah times)
            if (fajrTrigger > 0) {
                scheduleExact(context, 521, fajrTrigger + 30 * 60_000L, "ADHKAR_MORNING", "")
            }
            if (asrTrigger > 0) {
                scheduleExact(context, 522, asrTrigger + 30 * 60_000L, "ADHKAR_EVENING", "")
            }
            // Surah al-Mulk near bedtime: ~100 min after Isha
            if (ishaTrigger > 0) {
                scheduleExact(context, 523, ishaTrigger + 100 * 60_000L, "MULK_REMINDER", "")
            }
        }

        Log.d(TAG, "rescheduleAll: armed ${prayers.size} prayers (+extras)")
    }

    private data class WakeAlarmConfig(
        val systemEnabled: Boolean,
        val fajrEnabled: Boolean,
        val ishaEnabled: Boolean,
        val beforeFajrMinutes: Int,
        val afterFajrMinutes: Int,
    ) {
        fun controls(prayerName: String): Boolean {
            if (!systemEnabled) return false
            return when (prayerName) {
                "FAJR" -> fajrEnabled
                "ISHA" -> ishaEnabled
                else -> false
            }
        }

        companion object {
            fun fromPrefs(prefs: SharedPreferences): WakeAlarmConfig {
                val before = intPref(
                    prefs,
                    "flutter.fajr_alarm_start_before_fajr_min",
                    0,
                ).coerceIn(0, 60)
                val after = intPref(
                    prefs,
                    "flutter.fajr_alarm_start_after_fajr_min",
                    0,
                ).coerceAtLeast(0)
                return WakeAlarmConfig(
                    systemEnabled = prefs.getBoolean("flutter.fajr_alarm_system_enabled", false),
                    fajrEnabled = prefs.getBoolean("flutter.fajr_alarm_fajr_enabled", false),
                    ishaEnabled = prefs.getBoolean("flutter.fajr_alarm_isha_enabled", false),
                    beforeFajrMinutes = before,
                    afterFajrMinutes = if (before > 0) 0 else after,
                )
            }
        }
    }

    private fun intPref(prefs: SharedPreferences, key: String, defaultValue: Int): Int {
        return (prefs.all[key] as? Number)?.toInt() ?: defaultValue
    }

    private fun scheduleWakeAlarms(context: Context, config: WakeAlarmConfig) {
        if (!config.systemEnabled) {
            cancel(context, WAKE_FAJR_ID)
            cancel(context, WAKE_ISHA_ID)
            cancel(context, WAKE_AUTO_STOP_ID)
            cancel(context, WAKE_RETURN_ID)
            return
        }

        val prayers = PrayerStore.load(context, includeSunrise = true)
        val fajr = prayers.firstOrNull { it.name == "FAJR" }
        val sunrise = prayers.firstOrNull { it.name == "SUNRISE" }
        val isha = prayers.firstOrNull { it.name == "ISHA" }

        if (config.fajrEnabled && fajr != null && sunrise != null) {
            val trigger = fajrWakeTrigger(config, fajr, sunrise)
            scheduleExact(context, WAKE_FAJR_ID, trigger, WAKE_FAJR_NAME, "")
        } else {
            cancel(context, WAKE_FAJR_ID)
        }

        if (config.ishaEnabled && isha != null) {
            scheduleExact(context, WAKE_ISHA_ID, nextOccurrence(isha), WAKE_ISHA_NAME, "")
        } else {
            cancel(context, WAKE_ISHA_ID)
        }
    }

    private fun fajrWakeTrigger(
        config: WakeAlarmConfig,
        fajr: PrayerStore.Prayer,
        sunrise: PrayerStore.Prayer,
    ): Long {
        val now = System.currentTimeMillis()
        val fajrTime = nextOccurrence(fajr)
        var sunriseTime = nextOccurrence(sunrise)
        if (sunriseTime <= fajrTime) sunriseTime += 24 * 60 * 60 * 1000L

        val fajrToSunriseMinutes = ((sunriseTime - fajrTime) / 60_000L).toInt()
        val maxAfter = ((fajrToSunriseMinutes - 15).coerceAtLeast(0) / 5) * 5
        val afterMinutes = config.afterFajrMinutes.coerceIn(0, maxAfter)

        var trigger = when {
            config.beforeFajrMinutes > 0 -> fajrTime - config.beforeFajrMinutes * 60_000L
            afterMinutes > 0 -> fajrTime + afterMinutes * 60_000L
            else -> fajrTime
        }

        if (trigger <= now + 5_000L) {
            trigger = if (now < sunriseTime) now + 1_000L
            else trigger + 24 * 60 * 60 * 1000L
        }
        return trigger
    }

    fun scheduleWakeAutoStopAtSunrise(context: Context) {
        val sunrise = PrayerStore.load(context, includeSunrise = true)
            .firstOrNull { it.name == "SUNRISE" }
            ?: return
        scheduleExact(context, WAKE_AUTO_STOP_ID, nextOccurrence(sunrise), WAKE_AUTO_STOP_NAME, "")
    }

    fun stopWakeAlarmAtSunrise(context: Context) {
        cancel(context, WAKE_AUTO_STOP_ID)
        cancel(context, WAKE_RETURN_ID)
        cancel(context, SNOOZE_ID)

        val activityIntent = Intent(context, AdhanAlarmActivity::class.java).apply {
            putExtra("auto_stop_wake_alarm", true)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
        }
        try {
            context.startActivity(activityIntent)
        } catch (e: Exception) {
            Log.w(TAG, "sunrise auto-stop startActivity failed: ${e.message}")
        }
    }

    /** Re-fire an adhkar full-screen reveal after [minutes]. */
    fun scheduleAdhkarReminder(context: Context, type: String, minutes: Int) {
        val prayerName = when (type) {
            "evening" -> "ADHKAR_EVENING"
            "mulk" -> "MULK_REMINDER"
            else -> "ADHKAR_MORNING"
        }
        scheduleExact(
            context, ADHKAR_REMIND_ID,
            System.currentTimeMillis() + minutes * 60_000L, prayerName, "",
        )
    }

    /** Cancel one alarm by its stable ID. */
    fun cancel(context: Context, alarmId: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pi = PendingIntent.getBroadcast(
            context, alarmId,
            Intent(context, AdhanAlarmReceiver::class.java), piFlags,
        )
        am.cancel(pi)
    }

    /** Next future epoch-millis for a prayer's HH:MM (today if ahead, else tomorrow). */
    private fun nextOccurrence(prayer: PrayerStore.Prayer): Long {
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, prayer.hour)
            set(Calendar.MINUTE, prayer.minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        // If the time already passed (5s guard), roll to tomorrow.
        if (cal.timeInMillis <= System.currentTimeMillis() + 5000L) {
            cal.add(Calendar.DAY_OF_YEAR, 1)
        }
        return cal.timeInMillis
    }

    /**
     * Arm one exact alarm. Uses [AlarmManager.setAlarmClock] first because it
     * has the highest scheduling priority, fires through Doze, and does NOT
     * require the SCHEDULE_EXACT_ALARM special permission.
     */
    fun scheduleExact(
        context: Context,
        alarmId: Int,
        triggerAtMillis: Long,
        prayerName: String,
        soundKey: String,
    ) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val fireIntent = Intent(context, AdhanAlarmReceiver::class.java).apply {
            putExtra("prayer_name", prayerName)
            putExtra("sound_key", soundKey)
        }
        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val operation = PendingIntent.getBroadcast(context, alarmId, fireIntent, piFlags)

        // Tapping the status-bar alarm icon opens the app.
        val showPi = PendingIntent.getActivity(
            context, alarmId,
            Intent(context, MainActivity::class.java),
            piFlags,
        )

        try {
            am.setAlarmClock(AlarmManager.AlarmClockInfo(triggerAtMillis, showPi), operation)
            Log.d(
                TAG,
                "setAlarmClock $prayerName id=$alarmId in " +
                    "${(triggerAtMillis - System.currentTimeMillis()) / 1000}s",
            )
        } catch (e: Exception) {
            // Fallback path if setAlarmClock is unavailable.
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    !am.canScheduleExactAlarms()
                ) {
                    // No exact-alarm permission: best-effort inexact-but-doze alarm.
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, operation)
                    Log.w(TAG, "exact not allowed, used setAndAllowWhileIdle for $prayerName")
                } else {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, operation)
                    Log.d(TAG, "setExactAndAllowWhileIdle for $prayerName")
                }
            } catch (ex: Exception) {
                Log.e(TAG, "all alarm methods failed for $prayerName: ${ex.message}")
            }
        }
    }
}

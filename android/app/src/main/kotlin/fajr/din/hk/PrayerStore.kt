package fajr.din.hk

import android.content.Context
import android.util.Log
import org.json.JSONArray
import java.util.Calendar

/**
 * Shared native reader for the prayer times that Flutter persists to
 * SharedPreferences (`flutter.prayer_times_json`). Used by the alarm
 * scheduler, the home-screen widget and the lock-screen info service so they
 * all stay correct without the Flutter engine running.
 */
object PrayerStore {
    private const val TAG = "PrayerStore"
    private const val PREFS = "FlutterSharedPreferences"
    private const val KEY_TIMES = "flutter.prayer_times_json"

    val ARABIC_NAMES = mapOf(
        "FAJR" to "الفجر",
        "SUNRISE" to "الشروق",
        "DHUHR" to "الظهر",
        "ASR" to "العصر",
        "MAGHRIB" to "المغرب",
        "ISHA" to "العشاء",
    )

    data class Prayer(val name: String, val hour: Int, val minute: Int) {
        val minutesOfDay: Int get() = hour * 60 + minute
        val arabicName: String get() = ARABIC_NAMES[name] ?: name
        val timeLabel: String get() = String.format("%02d:%02d", hour, minute)
    }

    /** All saved prayers in time order (SUNRISE excluded by default — no adhan). */
    fun load(context: Context, includeSunrise: Boolean = false): List<Prayer> {
        val out = ArrayList<Prayer>()
        try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val json = prefs.getString(KEY_TIMES, null) ?: return out
            val arr = JSONArray(json)
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val name = o.optString("name")
                if (name.isEmpty() || (name == "SUNRISE" && !includeSunrise)) continue
                val parts = o.optString("time").split(":")
                if (parts.size != 2) continue
                val h = parts[0].trim().toIntOrNull() ?: continue
                val m = parts[1].trim().toIntOrNull() ?: continue
                out.add(Prayer(name, h, m))
            }
            out.sortBy { it.minutesOfDay }
        } catch (e: Exception) {
            // Direct-boot (locked device) can't read credential-protected prefs;
            // callers treat an empty list as "nothing to do yet".
            Log.w(TAG, "load failed: ${e.message}")
        }
        return out
    }

    /** The prayer whose time window we are currently inside (Isha wraps past midnight). */
    fun current(prayers: List<Prayer>): Prayer? {
        if (prayers.isEmpty()) return null
        val now = Calendar.getInstance()
        val nowMin = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        return prayers.lastOrNull { it.minutesOfDay <= nowMin } ?: prayers.last()
    }

    /**
     * Same as [current] but splits the sunrise→Dhuhr window into two phases:
     *   - First 15 min after sunrise → "الشروق"
     *   - After that until Dhuhr → "الضحى"
     * Returns Pair(displayName, internalName).
     */
    fun currentDisplay(prayers: List<Prayer>): Pair<String, String> {
        val raw = current(prayers)
        if (raw == null) return "—" to "—"

        if (raw.name != "SUNRISE") return raw.arabicName to raw.name

        val now = Calendar.getInstance()
        val nowMin = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val srMin = raw.minutesOfDay
        val duhaStartMin = (srMin + 15) % (24 * 60)

        val normNow = if (nowMin < srMin) nowMin + 24 * 60 else nowMin
        val normDuha = if (duhaStartMin < srMin) duhaStartMin + 24 * 60 else duhaStartMin

        return if (normNow < normDuha) "الشروق" to "SUNRISE"
        else "الضحى" to "DUHA"
    }

    /** The next upcoming prayer and its absolute epoch-millis trigger time. */
    fun next(prayers: List<Prayer>): Pair<Prayer, Long>? {
        if (prayers.isEmpty()) return null
        val now = Calendar.getInstance()
        val nowMin = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val upcoming = prayers.firstOrNull { it.minutesOfDay > nowMin }
        val target = upcoming ?: prayers.first() // none left today -> Fajr tomorrow
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, target.hour)
            set(Calendar.MINUTE, target.minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (upcoming == null) add(Calendar.DAY_OF_YEAR, 1)
        }
        return target to cal.timeInMillis
    }
}

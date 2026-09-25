package fajr.din.hk

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.RemoteViews

/**
 * "All prayer times" widget: a live clock + countdown header and a strip of all
 * six daily times (Fajr → Isha) with the current prayer highlighted in gold.
 */
class PrayerWidgetAllProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (widgetId in appWidgetIds) {
            try { setViews(context, appWidgetManager, widgetId) } catch (_: Exception) {}
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == "fajr.din.hk.UPDATE_WIDGET") refresh(context)
    }

    companion object {
        private const val TAG = "WidgetAll"
        private const val GOLD = 0xFFD4A853.toInt()
        private const val NAME_DIM = 0xFF9A9588.toInt()
        private const val TIME_LIGHT = 0xFFF0EDE4.toInt()

        private val SLOT_ORDER = listOf("FAJR", "SUNRISE", "DHUHR", "ASR", "MAGHRIB", "ISHA")

        private val NAME_IDS = intArrayOf(
            R.id.all_p0_name, R.id.all_p1_name, R.id.all_p2_name,
            R.id.all_p3_name, R.id.all_p4_name, R.id.all_p5_name,
        )
        private val TIME_IDS = intArrayOf(
            R.id.all_p0_time, R.id.all_p1_time, R.id.all_p2_time,
            R.id.all_p3_time, R.id.all_p4_time, R.id.all_p5_time,
        )

        @JvmStatic
        fun refresh(context: Context) {
            try {
                val mgr = AppWidgetManager.getInstance(context)
                val ids = mgr.getAppWidgetIds(
                    ComponentName(context, PrayerWidgetAllProvider::class.java),
                )
                for (widgetId in ids) setViews(context, mgr, widgetId)
            } catch (e: Exception) {
                Log.e(TAG, "refresh failed: ${e.message}", e)
            }
        }

        private fun setViews(context: Context, mgr: AppWidgetManager, widgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.prayer_widget_all)

            val prayers = PrayerStore.load(context, includeSunrise = true)
            val byName = prayers.associateBy { it.name }
            val current = PrayerStore.current(prayers.filter { it.name != "SUNRISE" })

            for (slot in 0 until SLOT_ORDER.size) {
                val key = SLOT_ORDER[slot]
                val p = byName[key]
                val highlighted = current?.name == key
                views.setTextViewText(
                    NAME_IDS[slot],
                    p?.arabicName ?: (PrayerStore.ARABIC_NAMES[key] ?: "--"),
                )
                views.setTextViewText(TIME_IDS[slot], p?.timeLabel ?: "--:--")
                views.setTextColor(NAME_IDS[slot], if (highlighted) GOLD else NAME_DIM)
                views.setTextColor(TIME_IDS[slot], if (highlighted) GOLD else TIME_LIGHT)
            }

            views.setTextViewText(
                R.id.widget_current_name,
                current?.arabicName ?: "--",
            )

            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val pen = PendingIntent.getActivity(
                context, 0, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, pen)
            mgr.updateAppWidget(widgetId, views)
        }
    }
}

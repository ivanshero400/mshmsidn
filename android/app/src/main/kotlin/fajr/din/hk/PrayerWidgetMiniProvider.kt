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
 * Minimum-height prayer widget: a single compact row (next prayer + live
 * countdown) that always fits even at the smallest resize.
 */
class PrayerWidgetMiniProvider : AppWidgetProvider() {

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
        private const val TAG = "WidgetMini"

        @JvmStatic
        fun refresh(context: Context) {
            try {
                val mgr = AppWidgetManager.getInstance(context)
                val ids = mgr.getAppWidgetIds(
                    ComponentName(context, PrayerWidgetMiniProvider::class.java),
                )
                for (widgetId in ids) setViews(context, mgr, widgetId)
            } catch (e: Exception) {
                Log.e(TAG, "refresh failed: ${e.message}", e)
            }
        }

        private fun setViews(context: Context, mgr: AppWidgetManager, widgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.prayer_widget_mini)

            val prayers = PrayerStore.load(context)
            val next = PrayerStore.next(prayers)

            views.setTextViewText(R.id.widget_next_name, next?.first?.arabicName ?: "--")
            views.setTextViewText(R.id.widget_next_time, next?.first?.timeLabel ?: "--:--")

            // Safe countdown: compute text manually instead of Chronometer
            val countdownText = if (next != null) {
                val remaining = (next.second - System.currentTimeMillis()) / 1000
                if (remaining > 0) {
                    val h = remaining / 3600
                    val m = (remaining % 3600) / 60
                    val s = remaining % 60
                    "%02d:%02d:%02d".format(h, m, s)
                } else "--:--:--"
            } else "--:--:--"
            views.setTextViewText(R.id.widget_countdown, countdownText)

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

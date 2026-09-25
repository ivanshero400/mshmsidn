package fajr.din.hk

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Adhkar widget: surfaces the dhikr appropriate for the current time (morning
 * before noon, evening after) and rotates through the set over the day so each
 * refresh shows a different one. Tapping opens the in-app adhkar screen with
 * the matching set (the chosen type is persisted for Flutter to read).
 */
class AdhkarWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (widgetId in appWidgetIds) setViews(context, appWidgetManager, widgetId)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == "fajr.din.hk.UPDATE_WIDGET") refresh(context)
    }

    companion object {
        @JvmStatic
        fun refresh(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(
                ComponentName(context, AdhkarWidgetProvider::class.java),
            )
            for (widgetId in ids) setViews(context, mgr, widgetId)
        }

        private fun setViews(context: Context, mgr: AppWidgetManager, widgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.adhkar_widget)

            val type = AdhkarStore.currentType()
            val item = AdhkarStore.currentItem(type)
            AdhkarStore.persistType(context, type)

            views.setTextViewText(R.id.adhkar_title, AdhkarStore.titleFor(type))
            views.setTextViewText(R.id.adhkar_count, item.count)
            views.setTextViewText(R.id.adhkar_text, item.text)
            views.setTextViewText(
                R.id.adhkar_source,
                if (item.source.isNotEmpty()) item.source else "اضغط لفتح الأذكار",
            )

            val intent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN
                addCategory(Intent.CATEGORY_LAUNCHER)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("route", "/adhkar-display")
            }
            val pen = PendingIntent.getActivity(
                context, 1, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, pen)
            mgr.updateAppWidget(widgetId, views)
        }
    }
}

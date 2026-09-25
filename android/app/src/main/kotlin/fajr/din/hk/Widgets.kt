package fajr.din.hk

import android.content.Context

/** Refreshes every home-screen widget this app provides in one call. */
object Widgets {
    @JvmStatic
    fun refreshAll(context: Context) {
        PrayerWidgetProvider.refresh(context)
        PrayerWidgetMiniProvider.refresh(context)
        AdhkarWidgetProvider.refresh(context)
    }
}

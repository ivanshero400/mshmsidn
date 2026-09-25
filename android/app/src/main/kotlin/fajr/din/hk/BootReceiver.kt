package fajr.din.hk

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Re-arms all prayer alarms after events that wipe AlarmManager state:
 * device reboot, app update, and clock / timezone changes.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("AdhanAlarm", "BootReceiver: ${intent.action} -> rescheduling alarms")
        try {
            AlarmScheduler.rescheduleAll(context)
        } catch (e: Exception) {
            Log.e("AdhanAlarm", "BootReceiver reschedule failed: ${e.message}")
        }
        // Restore the widget and the persistent lock-screen notification too
        // (BOOT_COMPLETED is exempt from background FGS-start restrictions).
        try {
            Widgets.refreshAll(context)
            PrayerInfoService.start(context)
        } catch (e: Exception) {
            Log.e("AdhanAlarm", "BootReceiver widget/service restore failed: ${e.message}")
        }
    }
}

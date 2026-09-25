package fajr.din.hk

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class AdhanAlarmActivity : FlutterActivity() {
    companion object {
        var prayerName: String = ""
        var soundKey: String = ""
        var adhkarType: String = ""
    }

    private val alarmSchedulerChannel = "azan.adhan.alarm_scheduler"

    private var normalAdhanActive = false
    private var normalAdhanMuted = false
    private var wakeAlarmActive = false
    private var activeWakeAlarmName = AlarmScheduler.WAKE_FAJR_NAME
    private var allowAlarmExit = false
    private var lastReturnReason = ""
    private val returnToFrontHandler = Handler(Looper.getMainLooper())
    private val returnToFrontRunnable = Runnable {
        returnFajrAlarmToFront(lastReturnReason)
    }
    private val alarmVolumeGuardHandler = Handler(Looper.getMainLooper())
    private var alarmAudioGuardActive = false
    private var originalMusicVolume: Int? = null
    private val alarmVolumeGuardRunnable = object : Runnable {
        override fun run() {
            if (!alarmAudioGuardActive) return
            forceAlarmMusicVolume()
            alarmVolumeGuardHandler.postDelayed(this, 500L)
        }
    }

    // ── Vibration (for "vibrate only" / "vibrate with adhan" modes) ──
    private fun vibratorService(): Vibrator {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
    }

    private fun startVibration() {
        try {
            val v = vibratorService()
            // wait 0, buzz 700, pause 500 — repeat indefinitely (index 0)
            val pattern = longArrayOf(0, 700, 500)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                v.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(pattern, 0)
            }
        } catch (e: Exception) {
            Log.e("AdhanAlarm", "startVibration failed: ${e.message}")
        }
    }

    private fun stopVibration() {
        try {
            vibratorService().cancel()
        } catch (_: Exception) {}
    }

    override fun getInitialRoute(): String {
        val pName = intent?.getStringExtra("prayer_name") ?: prayerName
        if (intent?.getBooleanExtra("auto_stop_wake_alarm", false) == true) {
            return "/fajr-alarm-active"
        }

        // Adhkar full-screen reveal (morning / evening / Surah al-Mulk)
        val adhkar = intent?.getStringExtra("adhkar_type")
        if (adhkar != null) return "/adhkar-display"

        if (AlarmScheduler.isWakeAlarmName(pName)) {
            Log.d("AdhanAlarm", "Using wake alarm screen for $pName")
            activateWakeAlarmGuard(pName)
            return "/fajr-alarm-active"
        }

        // All prayer alarms route to the normal adhan screen
        Log.d("AdhanAlarm", "Using normal adhan for $pName")
        normalAdhanActive = true
        return "/adhan-alarm"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        prayerName = intent?.getStringExtra("prayer_name") ?: prayerName
        soundKey = intent?.getStringExtra("sound_key") ?: soundKey
        adhkarType = intent?.getStringExtra("adhkar_type") ?: adhkarType
        Log.d("AdhanAlarm", "onCreate prayer=$prayerName adhkar=$adhkarType")
        applyAlarmWindowFlags()
        if (intent?.getBooleanExtra("auto_stop_wake_alarm", false) == true) {
            finishWakeAlarmFromSunrise()
            return
        }

        // If the user disabled the full-screen adhan, skip it entirely.
        val prefs = applicationContext.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        val screenEnabled = prefs.getBoolean("flutter.adhan_screen_enabled", true)
        val isAdhkar = intent?.getStringExtra("adhkar_type") != null
        val isWakeAlarm = AlarmScheduler.isWakeAlarmName(prayerName)
        if (isWakeAlarm) activateWakeAlarmGuard(prayerName)
        if (!screenEnabled && !isAdhkar && !isWakeAlarm) {
            Log.d("AdhanAlarm", "Screen disabled – finishing, notification only")
            finish()
            return
        }

        // The full-screen alarm screen is now showing, so dismiss the
        // backing full-screen-intent notification.
        (applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager)
            .cancel(AdhanAlarmReceiver.NOTIF_ID)
    }

    override fun onDestroy() {
        if (wakeAlarmGuardActive()) {
            Log.w("AdhanAlarm", "Wake alarm destroyed before stop — scheduling immediate return")
            scheduleImmediateWakeAlarmReturn("destroy")
        }
        returnToFrontHandler.removeCallbacks(returnToFrontRunnable)
        // If the normal adhan was active when the Activity got killed
        // (accidental back / system), force full cleanup so the sound
        // doesn't linger. Challenge (heavy/medium) has its own watchdog.
        if (normalAdhanActive || (wakeAlarmActive && allowAlarmExit)) {
            Log.w("AdhanAlarm", "Activity destroyed while normal adhan active — forcing cleanup")
            normalAdhanActive = false
            wakeAlarmActive = false
            stopAlarmAudioGuard(restore = true)
            stopVibration()
        } else if (wakeAlarmActive) {
            alarmVolumeGuardHandler.removeCallbacks(alarmVolumeGuardRunnable)
        }
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        prayerName = intent.getStringExtra("prayer_name") ?: prayerName
        soundKey = intent.getStringExtra("sound_key") ?: soundKey
        adhkarType = intent.getStringExtra("adhkar_type") ?: adhkarType
        if (intent.getBooleanExtra("auto_stop_wake_alarm", false)) {
            finishWakeAlarmFromSunrise()
            return
        }
        if (AlarmScheduler.isWakeAlarmName(prayerName)) {
            activateWakeAlarmGuard(prayerName)
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        requestFajrAlarmReturn("userLeaveHint", 120L)
    }

    override fun onPause() {
        super.onPause()
        requestFajrAlarmReturn("pause", 220L)
    }

    override fun onStop() {
        super.onStop()
        requestFajrAlarmReturn("stop", 320L)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus) requestFajrAlarmReturn("focusLost", 180L)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action != KeyEvent.ACTION_DOWN) return super.dispatchKeyEvent(event)

        // Normal adhan: volume controls mute/unmute the sound
        if (normalAdhanActive) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    if (!normalAdhanMuted) muteAdhanSound()
                    return true
                }
                KeyEvent.KEYCODE_VOLUME_UP -> {
                    if (normalAdhanMuted) unmuteAdhanSound()
                    return true
                }
            }
        }

        if (wakeAlarmActive) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_VOLUME_DOWN,
                KeyEvent.KEYCODE_VOLUME_UP,
                KeyEvent.KEYCODE_VOLUME_MUTE -> {
                    forceAlarmMusicVolume()
                    return true
                }
            }
        }

        return super.dispatchKeyEvent(event)
    }

    private fun muteAdhanSound() {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am.setStreamVolume(AudioManager.STREAM_MUSIC, 0, 0)
            normalAdhanMuted = true
        } catch (_: Exception) {}
    }

    private fun unmuteAdhanSound() {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val level = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC) / 2
            am.setStreamVolume(AudioManager.STREAM_MUSIC, level, 0)
            normalAdhanMuted = false
        } catch (_: Exception) {}
    }

    private fun startAlarmAudioGuard() {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (originalMusicVolume == null) {
                originalMusicVolume = am.getStreamVolume(AudioManager.STREAM_MUSIC)
            }
            alarmAudioGuardActive = true
            forceAlarmMusicVolume()
            alarmVolumeGuardHandler.removeCallbacks(alarmVolumeGuardRunnable)
            alarmVolumeGuardHandler.postDelayed(alarmVolumeGuardRunnable, 500L)
        } catch (e: Exception) {
            Log.e("AdhanAlarm", "startAlarmAudioGuard failed: ${e.message}")
        }
    }

    private fun stopAlarmAudioGuard(restore: Boolean) {
        alarmAudioGuardActive = false
        alarmVolumeGuardHandler.removeCallbacks(alarmVolumeGuardRunnable)
        if (!restore) return
        try {
            val previous = originalMusicVolume
            if (previous != null) {
                val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                am.setStreamVolume(AudioManager.STREAM_MUSIC, previous.coerceIn(0, max), 0)
            }
        } catch (e: Exception) {
            Log.e("AdhanAlarm", "stopAlarmAudioGuard failed: ${e.message}")
        } finally {
            originalMusicVolume = null
        }
    }

    private fun forceAlarmMusicVolume() {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            am.setStreamVolume(AudioManager.STREAM_MUSIC, max, 0)
        } catch (_: Exception) {}
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (normalAdhanActive || wakeAlarmActive) return
        super.onBackPressed()
    }

    private fun activateWakeAlarmGuard(name: String) {
        wakeAlarmActive = true
        activeWakeAlarmName = if (AlarmScheduler.isWakeAlarmName(name)) {
            name
        } else {
            AlarmScheduler.WAKE_FAJR_NAME
        }
        allowAlarmExit = false
        normalAdhanActive = false
        normalAdhanMuted = false
        startAlarmAudioGuard()
    }

    private fun wakeAlarmGuardActive(): Boolean {
        return wakeAlarmActive && !allowAlarmExit && !isFinishing
    }

    private fun applyAlarmWindowFlags() {
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
    }

    private fun requestFajrAlarmReturn(reason: String, delayMs: Long) {
        if (!wakeAlarmGuardActive()) return
        lastReturnReason = reason
        returnToFrontHandler.removeCallbacks(returnToFrontRunnable)
        returnToFrontHandler.postDelayed(returnToFrontRunnable, delayMs)
    }

    @Suppress("DEPRECATION")
    private fun returnFajrAlarmToFront(reason: String) {
        if (!wakeAlarmGuardActive()) return
        Log.w("AdhanAlarm", "Returning wake alarm to foreground after $reason")

        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            am.moveTaskToFront(taskId, ActivityManager.MOVE_TASK_WITH_HOME)
        } catch (e: Exception) {
            Log.w("AdhanAlarm", "moveTaskToFront failed: ${e.message}")
        }

        val launchIntent = Intent(this, AdhanAlarmActivity::class.java).apply {
            putExtra("prayer_name", activeWakeAlarmName)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        }
        try {
            startActivity(launchIntent)
        } catch (e: Exception) {
            Log.w("AdhanAlarm", "foreground return startActivity failed: ${e.message}")
            scheduleImmediateWakeAlarmReturn("startActivityFailure")
        }
    }

    private fun scheduleImmediateWakeAlarmReturn(reason: String) {
        if (allowAlarmExit) return
        Log.w("AdhanAlarm", "Scheduling immediate wake alarm return after $reason")
        try {
            AlarmScheduler.scheduleExact(
                applicationContext,
                AlarmScheduler.WAKE_RETURN_ID,
                System.currentTimeMillis() + 1_000L,
                activeWakeAlarmName,
                soundKey,
            )
        } catch (e: Exception) {
            Log.e("AdhanAlarm", "schedule immediate return failed: ${e.message}")
        }
    }

    private fun finishWakeAlarmFromSunrise() {
        allowAlarmExit = true
        normalAdhanActive = false
        normalAdhanMuted = false
        wakeAlarmActive = false
        returnToFrontHandler.removeCallbacks(returnToFrontRunnable)
        AlarmScheduler.cancel(applicationContext, AlarmScheduler.WAKE_AUTO_STOP_ID)
        AlarmScheduler.cancel(applicationContext, AlarmScheduler.WAKE_RETURN_ID)
        AlarmScheduler.cancel(applicationContext, AlarmScheduler.SNOOZE_ID)
        stopAlarmAudioGuard(restore = true)
        stopVibration()
        finish()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, alarmSchedulerChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleAlarm" -> {
                    val args = call.arguments as Map<String, Any>
                    val alarmId = args["alarmId"] as Int
                    val triggerAtMillis = args["triggerAtMillis"] as Long
                    val pName = args["prayerName"] as? String ?: ""
                    val sKey = args["soundKey"] as? String ?: ""
                    AlarmScheduler.scheduleExact(applicationContext, alarmId, triggerAtMillis, pName, sKey)
                    result.success(true)
                }
                "cancelAlarm" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: 0
                    AlarmScheduler.cancel(applicationContext, alarmId)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "azan.adhan.alarm").setMethodCallHandler { call, result ->
            when (call.method) {
                "getAlarmData" -> {
                    result.success(mapOf(
                        "prayerName" to prayerName,
                        "soundKey" to soundKey,
                        "adhkarType" to adhkarType,
                    ))
                }
                "scheduleAdhkarReminder" -> {
                    val type = call.argument<String>("type") ?: "morning"
                    val minutes = call.argument<Int>("minutes") ?: 15
                    AlarmScheduler.scheduleAdhkarReminder(applicationContext, type, minutes)
                    finish()
                    result.success(true)
                }
                "startVibration" -> {
                    startVibration()
                    result.success(true)
                }
                "stopVibration" -> {
                    stopVibration()
                    result.success(true)
                }
                "startAlarmAudioGuard" -> {
                    startAlarmAudioGuard()
                    result.success(true)
                }
                "stopAlarmAudioGuard" -> {
                    val restore = call.argument<Boolean>("restore") ?: true
                    stopAlarmAudioGuard(restore)
                    result.success(true)
                }
                "stopAlarm" -> {
                    allowAlarmExit = true
                    normalAdhanActive = false
                    normalAdhanMuted = false
                    wakeAlarmActive = false
                    returnToFrontHandler.removeCallbacks(returnToFrontRunnable)
                    AlarmScheduler.cancel(applicationContext, AlarmScheduler.WAKE_AUTO_STOP_ID)
                    AlarmScheduler.cancel(applicationContext, AlarmScheduler.WAKE_RETURN_ID)
                    AlarmScheduler.cancel(applicationContext, AlarmScheduler.SNOOZE_ID)
                    stopAlarmAudioGuard(restore = true)
                    stopVibration()
                    finish()
                    result.success(true)
                }
                "scheduleSnooze" -> {
                    allowAlarmExit = true
                    normalAdhanActive = false
                    normalAdhanMuted = false
                    wakeAlarmActive = false
                    returnToFrontHandler.removeCallbacks(returnToFrontRunnable)
                    stopAlarmAudioGuard(restore = true)
                    AlarmScheduler.cancel(applicationContext, AlarmScheduler.WAKE_RETURN_ID)
                    val minutes = call.argument<Int>("minutes") ?: 8
                    AlarmScheduler.scheduleExact(
                        applicationContext, AlarmScheduler.SNOOZE_ID,
                        System.currentTimeMillis() + minutes * 60_000L,
                        prayerName, soundKey,
                    )
                    finish()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}

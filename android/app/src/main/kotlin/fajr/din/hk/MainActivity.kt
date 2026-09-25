package fajr.din.hk

import android.app.Activity
import android.content.Intent
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val WIDGET_CHANNEL = "fajr.din.hk/widget"
    private val ALARM_CHANNEL = "azan.adhan.alarm_scheduler"
    private val CUSTOM_SOUND_CHANNEL = "azan.custom_sound"

    // Deep-link route attached by a tapped native notification (adhkar/Mulk…)
    private var pendingRoute: String? = null

    // Pending Flutter result while the system audio picker is open
    private var pendingSoundResult: MethodChannel.Result? = null
    private var pendingSoundKind: String = "adhan"
    private val pickAudioRequestCode = 6541
    private var alarmRecorder: MediaRecorder? = null
    private var alarmRecordingFile: File? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        pendingRoute = intent?.getStringExtra("route")
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra("route")?.let { pendingRoute = it }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Keep the app resident in the background (like call/messaging apps do)
        // via a persistent foreground service + lock-screen prayer notification.
        PrayerInfoService.start(this)

        // High-accuracy fused compass stream for the Qibla finder
        // (rotation vector + true-north declination + interference detection).
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "azan.qibla/sensors")
            .setStreamHandler(QiblaSensorManager(this))

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "updateWidget") {
                val args = call.arguments as Map<String, Any>
                val next = args["next"] as? String ?: ""
                val remaining = args["remaining"] as? String ?: ""
                PrayerWidgetProvider.updateData(applicationContext, next, remaining)
                result.success(true)
            } else { result.notImplemented() }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "rescheduleAll" -> {
                    // Read the prayer times Flutter saved to prefs and arm the
                    // next occurrence of every prayer (self-perpetuating).
                    Log.d("AdhanAlarm", "rescheduleAll requested from Flutter")
                    AlarmScheduler.rescheduleAll(applicationContext)
                    // Times may have changed (settings/API refresh): sync the
                    // widget and the lock-screen notification as well.
                    Widgets.refreshAll(applicationContext)
                    PrayerInfoService.start(applicationContext)
                    result.success(true)
                }
                "scheduleAlarm" -> {
                    val args = call.arguments as Map<String, Any>
                    val alarmId = args["alarmId"] as Int
                    val triggerAtMillis = args["triggerAtMillis"] as Long
                    val prayerName = args["prayerName"] as? String ?: ""
                    val soundKey = args["soundKey"] as? String ?: ""
                    Log.d("AdhanAlarm", "Scheduling alarm $alarmId for $prayerName at $triggerAtMillis (in ${(triggerAtMillis - System.currentTimeMillis()) / 1000}s)")
                    AlarmScheduler.scheduleExact(applicationContext, alarmId, triggerAtMillis, prayerName, soundKey)
                    result.success(true)
                }
                "cancelAll" -> { result.success(true) }
                "cancelAlarm" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: 0
                    AlarmScheduler.cancel(applicationContext, alarmId)
                    result.success(true)
                }
                "launchAlarmActivity" -> {
                    val args = call.arguments as Map<String, Any>
                    val prayerName = args["prayerName"] as? String ?: "الصلاة"
                    val soundKey = args["soundKey"] as? String ?: ""
                    Log.d("AdhanAlarm", "Direct launch of AdhanAlarmActivity for $prayerName")
                    val intent = Intent(this@MainActivity, AdhanAlarmActivity::class.java).apply {
                        putExtra("prayer_name", prayerName)
                        putExtra("sound_key", soundKey)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Custom adhan sound picker (Storage Access Framework → local copy)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CUSTOM_SOUND_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickAudio" -> {
                    openAudioPicker(result, "adhan")
                }
                "pickAlarmAudio" -> {
                    openAudioPicker(result, "alarm")
                }
                "startAlarmRecording" -> {
                    startAlarmRecording(result)
                }
                "stopAlarmRecording" -> {
                    stopAlarmRecording(result)
                }
                "cancelAlarmRecording" -> {
                    cancelAlarmRecording()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

    }

    private fun openAudioPicker(result: MethodChannel.Result, kind: String) {
        if (pendingSoundResult != null) {
            result.error("BUSY", "A picker is already open", null)
            return
        }
        pendingSoundResult = result
        pendingSoundKind = kind
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "audio/*"
                // Accept every audio container the device can decode
                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("audio/*"))
            }
            startActivityForResult(intent, pickAudioRequestCode)
        } catch (e: Exception) {
            pendingSoundResult = null
            pendingSoundKind = "adhan"
            result.error("NO_PICKER", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickAudioRequestCode) return
        val result = pendingSoundResult ?: return
        pendingSoundResult = null

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pendingSoundKind = "adhan"
            result.success(null) // user cancelled
            return
        }
        try {
            val kind = pendingSoundKind
            pendingSoundKind = "adhan"
            val name = queryDisplayName(uri)
            val ext = name.substringAfterLast('.', "mp3").lowercase()
            // Copy into private storage so it survives & plays offline forever
            val dirName = if (kind == "alarm") "fajr_alarm_audio" else "custom_adhan"
            val fileName = if (kind == "alarm") "alarm_sound.$ext" else "custom_sound.$ext"
            val dir = File(filesDir, dirName).apply { mkdirs() }
            val outFile = File(dir, fileName)
            contentResolver.openInputStream(uri)?.use { input ->
                outFile.outputStream().use { output -> input.copyTo(output) }
            }
            result.success(
                mapOf("path" to outFile.absolutePath, "name" to name.substringBeforeLast('.')),
            )
        } catch (e: Exception) {
            Log.e("CustomSound", "copy failed: ${e.message}")
            result.error("COPY_FAILED", e.message, null)
        }
    }

    private fun startAlarmRecording(result: MethodChannel.Result) {
        if (alarmRecorder != null) {
            result.error("BUSY", "A recording is already running", null)
            return
        }
        try {
            val dir = File(filesDir, "fajr_alarm_recordings").apply { mkdirs() }
            val outFile = File(dir, "alarm_recording_${System.currentTimeMillis()}.m4a")
            val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }
            recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recorder.setAudioSamplingRate(44100)
            recorder.setAudioEncodingBitRate(128000)
            recorder.setOutputFile(outFile.absolutePath)
            recorder.prepare()
            recorder.start()
            alarmRecorder = recorder
            alarmRecordingFile = outFile
            result.success(mapOf("path" to outFile.absolutePath, "name" to "Alarm recording"))
        } catch (e: Exception) {
            releaseAlarmRecorder(deleteFile = true)
            Log.e("CustomSound", "recording start failed: ${e.message}")
            result.error("RECORD_START_FAILED", e.message, null)
        }
    }

    private fun stopAlarmRecording(result: MethodChannel.Result) {
        val recorder = alarmRecorder
        val file = alarmRecordingFile
        if (recorder == null || file == null) {
            result.error("NO_RECORDING", "No recording is running", null)
            return
        }
        try {
            recorder.stop()
            recorder.release()
            alarmRecorder = null
            alarmRecordingFile = null
            result.success(mapOf("path" to file.absolutePath, "name" to "Alarm recording"))
        } catch (e: Exception) {
            releaseAlarmRecorder(deleteFile = true)
            Log.e("CustomSound", "recording stop failed: ${e.message}")
            result.error("RECORD_STOP_FAILED", e.message, null)
        }
    }

    private fun cancelAlarmRecording() {
        releaseAlarmRecorder(deleteFile = true)
    }

    private fun releaseAlarmRecorder(deleteFile: Boolean) {
        try {
            alarmRecorder?.release()
        } catch (_: Exception) {}
        if (deleteFile) {
            try {
                alarmRecordingFile?.delete()
            } catch (_: Exception) {}
        }
        alarmRecorder = null
        alarmRecordingFile = null
    }

    private fun queryDisplayName(uri: Uri): String {
        var name = "الصوت المخصص.mp3"
        try {
            contentResolver.query(uri, null, null, null, null)?.use { c ->
                val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && c.moveToFirst()) {
                    c.getString(idx)?.let { name = it }
                }
            }
        } catch (_: Exception) {}
        return name
    }

}

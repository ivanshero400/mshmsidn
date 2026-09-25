package fajr.din.hk

import android.content.Context
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.util.Log
import android.view.Surface
import io.flutter.plugin.common.EventChannel
import kotlin.math.sqrt

/**
 * High-accuracy compass stream for the Qibla finder.
 *
 * Accuracy stack (each layer removes a real-world error source):
 *  1. TYPE_ROTATION_VECTOR — hardware-fused gyro+accel+magnetometer. The gyro
 *     suppresses jitter and short-term magnetic noise; fusion handles tilt
 *     compensation far better than raw accel+mag math.
 *  2. remapCoordinateSystem for the current display rotation, so the heading
 *     is correct in portrait, landscape and reverse orientations.
 *  3. GeomagneticField (WMM model) declination correction — converts magnetic
 *     north to TRUE geographic north for the user's exact lat/lng/altitude.
 *     Skipping this is the single biggest error in most qibla apps (±15°+).
 *  4. Magnetometer accuracy reporting (drives real calibration UX, not timers).
 *  5. Magnetic-interference detection: compares measured field magnitude with
 *     the WMM-expected strength at this location; flags metal/magnet nearby.
 *  6. Graceful fallback to accelerometer+magnetometer fusion on devices
 *     without a rotation-vector sensor.
 *
 * Emits ~30 Hz maps:
 *   { heading: Double (TRUE-north 0..360), pitch: Double, roll: Double,
 *     accuracy: Int (0..3), fieldOk: Boolean, fieldMagnitude: Double,
 *     declination: Double, fused: Boolean }
 */
class QiblaSensorManager(private val context: Context) :
    EventChannel.StreamHandler, SensorEventListener {

    private var sensorManager: SensorManager? = null
    private var sink: EventChannel.EventSink? = null

    private var declination = 0f
    private var expectedFieldUt = 0f // expected geomagnetic strength, µT
    private var usingRotationVector = false

    private val rotMat = FloatArray(9)
    private val remapMat = FloatArray(9)
    private val orientation = FloatArray(3)

    private var magAccuracy = SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM
    private var fieldMagnitude = 0f
    private var lastEmitNs = 0L

    // Fallback fusion state (devices without rotation vector)
    private val grav = FloatArray(3)
    private val geo = FloatArray(3)
    private var hasGrav = false
    private var hasGeo = false

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        val args = arguments as? Map<*, *>
        val lat = (args?.get("lat") as? Number)?.toFloat() ?: 0f
        val lng = (args?.get("lng") as? Number)?.toFloat() ?: 0f
        val alt = (args?.get("alt") as? Number)?.toFloat() ?: 0f

        // World Magnetic Model: declination + expected field strength here & now.
        val gmf = GeomagneticField(lat, lng, alt, System.currentTimeMillis())
        declination = gmf.declination
        expectedFieldUt = gmf.fieldStrength / 1000f // nT → µT
        Log.d(TAG, "declination=$declination° expectedField=${expectedFieldUt}µT")

        val sm = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        sensorManager = sm

        val rotVec = sm.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        usingRotationVector = rotVec != null
        if (rotVec != null) {
            sm.registerListener(this, rotVec, SensorManager.SENSOR_DELAY_GAME)
        } else {
            // Fallback fusion: gravity (or accel) + magnetometer
            val gravity = sm.getDefaultSensor(Sensor.TYPE_GRAVITY)
                ?: sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            gravity?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) }
        }
        // Always observe the raw magnetometer: it carries the calibration
        // accuracy status and lets us detect magnetic interference.
        sm.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)?.let {
            sm.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
        }
    }

    override fun onCancel(arguments: Any?) {
        sensorManager?.unregisterListener(this)
        sensorManager = null
        sink = null
        hasGrav = false
        hasGeo = false
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        if (sensor?.type == Sensor.TYPE_MAGNETIC_FIELD ||
            sensor?.type == Sensor.TYPE_ROTATION_VECTOR
        ) {
            magAccuracy = accuracy
        }
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ROTATION_VECTOR -> {
                SensorManager.getRotationMatrixFromVector(rotMat, event.values)
                emitFromRotationMatrix(rotMat)
            }
            Sensor.TYPE_MAGNETIC_FIELD -> {
                geo[0] = event.values[0]; geo[1] = event.values[1]; geo[2] = event.values[2]
                hasGeo = true
                fieldMagnitude = sqrt(
                    geo[0] * geo[0] + geo[1] * geo[1] + geo[2] * geo[2],
                )
                if (event.accuracy != SensorManager.SENSOR_STATUS_NO_CONTACT) {
                    magAccuracy = event.accuracy
                }
                if (!usingRotationVector) emitFromFallbackFusion()
            }
            Sensor.TYPE_GRAVITY, Sensor.TYPE_ACCELEROMETER -> {
                // Low-pass only needed for raw accelerometer
                val a = if (event.sensor.type == Sensor.TYPE_ACCELEROMETER) 0.15f else 1f
                grav[0] += a * (event.values[0] - grav[0])
                grav[1] += a * (event.values[1] - grav[1])
                grav[2] += a * (event.values[2] - grav[2])
                hasGrav = true
                if (!usingRotationVector) emitFromFallbackFusion()
            }
        }
    }

    private fun emitFromFallbackFusion() {
        if (!hasGrav || !hasGeo) return
        if (!SensorManager.getRotationMatrix(rotMat, null, grav, geo)) return
        emitFromRotationMatrix(rotMat)
    }

    private fun emitFromRotationMatrix(matrix: FloatArray) {
        // Throttle to ~30 Hz
        val now = System.nanoTime()
        if (now - lastEmitNs < 33_000_000L) return
        lastEmitNs = now

        // Remap axes for the current screen rotation so heading stays correct
        // however the user holds the device.
        val rotation = displayRotation()
        val (axisX, axisY) = when (rotation) {
            Surface.ROTATION_90 -> SensorManager.AXIS_Y to SensorManager.AXIS_MINUS_X
            Surface.ROTATION_180 -> SensorManager.AXIS_MINUS_X to SensorManager.AXIS_MINUS_Y
            Surface.ROTATION_270 -> SensorManager.AXIS_MINUS_Y to SensorManager.AXIS_X
            else -> SensorManager.AXIS_X to SensorManager.AXIS_Y
        }
        SensorManager.remapCoordinateSystem(matrix, axisX, axisY, remapMat)
        SensorManager.getOrientation(remapMat, orientation)

        val magneticAzimuth = Math.toDegrees(orientation[0].toDouble())
        var trueHeading = magneticAzimuth + declination
        trueHeading = ((trueHeading % 360.0) + 360.0) % 360.0

        // Interference check: measured |B| should be near the WMM expectation.
        val fieldOk = expectedFieldUt <= 0f || fieldMagnitude <= 0f ||
            (fieldMagnitude > expectedFieldUt * 0.6f && fieldMagnitude < expectedFieldUt * 1.5f)

        sink?.success(
            mapOf(
                "heading" to trueHeading,
                "pitch" to Math.toDegrees(orientation[1].toDouble()),
                "roll" to Math.toDegrees(orientation[2].toDouble()),
                "accuracy" to magAccuracy,
                "fieldOk" to fieldOk,
                "fieldMagnitude" to fieldMagnitude.toDouble(),
                "declination" to declination.toDouble(),
                "fused" to usingRotationVector,
            ),
        )
    }

    @Suppress("DEPRECATION")
    private fun displayRotation(): Int = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            context.display?.rotation ?: Surface.ROTATION_0
        } else {
            (context.getSystemService(Context.WINDOW_SERVICE) as android.view.WindowManager)
                .defaultDisplay.rotation
        }
    } catch (e: Exception) {
        Surface.ROTATION_0
    }

    companion object {
        private const val TAG = "QiblaSensor"
    }
}

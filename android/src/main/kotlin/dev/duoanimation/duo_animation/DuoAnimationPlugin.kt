package dev.duoanimation.duo_animation

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.view.Surface
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.sqrt

/**
 * Streams screen-axes orientation to Dart.
 *
 * Rotation comes from TYPE_GAME_ROTATION_VECTOR: gyro plus accelerometer, no
 * magnetometer. Yaw is the exact axis the fold effect tracks, and magnetometer
 * fusion would trade latency for a long-term stability nobody needs here, so
 * the fused TYPE_ROTATION_VECTOR is only a fallback for devices that lack the
 * game sensor.
 *
 * The plugin deliberately does no filtering. It reduces each reading to screen
 * axes, projects the gyro onto the screen's up axis, and hands 13 doubles to
 * Dart, where calibration, prediction and washout live.
 */
class DuoAnimationPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    SensorEventListener {

    private lateinit var context: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var sensorManager: SensorManager? = null

    private var rotationSensor: Sensor? = null
    private var gyroSensor: Sensor? = null
    private var eventSink: EventChannel.EventSink? = null

    private val rawMatrix = FloatArray(9)
    private val screenMatrix = FloatArray(9)
    private val gyroRate = FloatArray(3)
    private var hasGyroSample = false
    private val payload = DoubleArray(PAYLOAD_LENGTH)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        rotationSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
            ?: sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        gyroSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopListening()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        sensorManager = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "metrics" -> result.success(
                mapOf(
                    "pixelsPerMillimeter" to pixelsPerMillimeter(),
                    "hasRotationSensor" to (rotationSensor != null)
                )
            )
            "stop" -> {
                stopListening()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        val manager = sensorManager ?: return
        rotationSensor?.let {
            manager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
        }
        gyroSensor?.let {
            manager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
        }
    }

    override fun onCancel(arguments: Any?) {
        stopListening()
    }

    private fun stopListening() {
        sensorManager?.unregisterListener(this)
        hasGyroSample = false
        eventSink = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_GYROSCOPE -> {
                gyroRate[0] = event.values[0]
                gyroRate[1] = event.values[1]
                gyroRate[2] = event.values[2]
                hasGyroSample = true
            }
            Sensor.TYPE_GAME_ROTATION_VECTOR, Sensor.TYPE_ROTATION_VECTOR -> {
                val sink = eventSink ?: return
                SensorManager.getRotationMatrixFromVector(rawMatrix, event.values)
                val (axisX, axisY) = screenRemapAxes()
                SensorManager.remapCoordinateSystem(rawMatrix, axisX, axisY, screenMatrix)

                for (i in 0 until 9) {
                    payload[i] = screenMatrix[i].toDouble()
                }

                val screenUp = screenUpInDeviceCoords()
                payload[9] = if (hasGyroSample) {
                    (gyroRate[0] * screenUp[0] +
                        gyroRate[1] * screenUp[1] +
                        gyroRate[2] * screenUp[2]).toDouble()
                } else {
                    0.0
                }
                payload[10] = if (hasGyroSample) {
                    sqrt(
                        gyroRate[0] * gyroRate[0] +
                            gyroRate[1] * gyroRate[1] +
                            gyroRate[2] * gyroRate[2]
                    ).toDouble()
                } else {
                    0.0
                }
                payload[11] = if (hasGyroSample) 1.0 else 0.0
                payload[12] = event.timestamp / 1_000_000_000.0

                sink.success(payload.copyOf())
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    /**
     * Axis pair for remapCoordinateSystem so the matrix columns come out as
     * screen-right, screen-up and screen-normal for the current display
     * rotation.
     */
    private fun screenRemapAxes(): Pair<Int, Int> = when (displayRotation()) {
        Surface.ROTATION_90 -> SensorManager.AXIS_Y to SensorManager.AXIS_MINUS_X
        Surface.ROTATION_180 -> SensorManager.AXIS_MINUS_X to SensorManager.AXIS_MINUS_Y
        Surface.ROTATION_270 -> SensorManager.AXIS_MINUS_Y to SensorManager.AXIS_X
        else -> SensorManager.AXIS_X to SensorManager.AXIS_Y
    }

    /** Screen-up expressed in raw device coordinates, for the gyro projection. */
    private fun screenUpInDeviceCoords(): FloatArray = when (displayRotation()) {
        Surface.ROTATION_90 -> floatArrayOf(-1f, 0f, 0f)
        Surface.ROTATION_180 -> floatArrayOf(0f, -1f, 0f)
        Surface.ROTATION_270 -> floatArrayOf(1f, 0f, 0f)
        else -> floatArrayOf(0f, 1f, 0f)
    }

    // defaultDisplay is deprecated but it is the only rotation source on API 24
    // through 29. Its replacement, context.display, needs API 30, and minSdk
    // here is 24, so the fallback stays.
    @Suppress("DEPRECATION")
    private fun displayRotation(): Int = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            context.display?.rotation ?: Surface.ROTATION_0
        } else {
            val windowManager =
                context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            windowManager.defaultDisplay.rotation
        }
    } catch (_: Exception) {
        Surface.ROTATION_0
    }

    /** Physical pixels per millimetre, from the display's horizontal DPI. */
    private fun pixelsPerMillimeter(): Double {
        val xdpi = context.resources.displayMetrics.xdpi
        return if (xdpi.isFinite() && xdpi > 0f) (xdpi / 25.4f).toDouble() else 0.0
    }

    private companion object {
        const val METHOD_CHANNEL = "dev.duoanimation/duo_animation"
        const val EVENT_CHANNEL = "dev.duoanimation/duo_animation/motion"
        const val PAYLOAD_LENGTH = 13
    }
}

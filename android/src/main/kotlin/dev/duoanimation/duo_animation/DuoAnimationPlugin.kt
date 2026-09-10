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
 * axes, projects the gyro onto the screen's up and right axes, and publishes a
 * MotionFrame to Dart, where calibration, prediction and washout live. The
 * schema at pigeons/motion.dart owns that contract; this file only fills it in.
 */
class DuoAnimationPlugin :
    FlutterPlugin,
    DuoMotionHostApi,
    SensorEventListener {

    private lateinit var context: Context
    private var sensorManager: SensorManager? = null

    private var rotationSensor: Sensor? = null
    private var gyroSensor: Sensor? = null
    private var eventSink: PigeonEventSink<MotionFrame>? = null
    private var streamHandler: MotionStreamHandler? = null

    private val rawMatrix = FloatArray(9)
    private val screenMatrix = FloatArray(9)
    private val gyroRate = FloatArray(3)
    private var hasGyroSample = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        rotationSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
            ?: sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        gyroSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

        DuoMotionHostApi.setUp(binding.binaryMessenger, this)
        val handler = MotionStreamHandler(this)
        streamHandler = handler
        StreamMotionStreamHandler.register(binding.binaryMessenger, handler)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopListening()
        DuoMotionHostApi.setUp(binding.binaryMessenger, null)
        // The generated register() takes a non-null handler and offers no undo, so
        // the event channel keeps this handler after detach. Dropping the plugin
        // reference is what stops that stale handler from pinning the plugin, and
        // with it the application context, for the life of the process.
        streamHandler?.detach()
        streamHandler = null
        sensorManager = null
    }

    override fun metrics(): MotionMetrics = MotionMetrics(
        pixelsPerMillimeter = pixelsPerMillimeter(),
        hasRotationSensor = rotationSensor != null
    )

    override fun stop() {
        stopListening()
    }

    /**
     * Registers sensor listeners while Dart is subscribed. The plugin itself
     * receives the sensor callbacks, so this only starts and stops them and
     * holds the sink to publish through.
     *
     * Deliberately not an inner class. The event channel outlives detach, so a
     * handler with an implicit reference to the plugin would keep it alive; this
     * one can be emptied with [detach].
     */
    private class MotionStreamHandler(
        private var plugin: DuoAnimationPlugin?
    ) : StreamMotionStreamHandler() {

        /** Drops the plugin reference once the engine is gone. */
        fun detach() {
            plugin = null
        }

        override fun onListen(p0: Any?, sink: PigeonEventSink<MotionFrame>) {
            plugin?.startListening(sink)
        }

        override fun onCancel(p0: Any?) {
            plugin?.stopListening()
        }
    }

    private fun startListening(sink: PigeonEventSink<MotionFrame>) {
        eventSink = sink
        val manager = sensorManager ?: return
        rotationSensor?.let {
            manager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
        }
        gyroSensor?.let {
            manager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
        }
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

                val matrix = DoubleArray(9) { screenMatrix[it].toDouble() }

                val screenUp = screenUpInDeviceCoords()
                val screenRight = screenRightInDeviceCoords()

                sink.success(
                    MotionFrame(
                        screenMatrix = matrix,
                        omegaScreenY = if (hasGyroSample) {
                            (gyroRate[0] * screenUp[0] +
                                gyroRate[1] * screenUp[1] +
                                gyroRate[2] * screenUp[2]).toDouble()
                        } else {
                            0.0
                        },
                        omegaScreenX = if (hasGyroSample) {
                            (gyroRate[0] * screenRight[0] +
                                gyroRate[1] * screenRight[1] +
                                gyroRate[2] * screenRight[2]).toDouble()
                        } else {
                            0.0
                        },
                        omegaMagnitude = if (hasGyroSample) {
                            sqrt(
                                gyroRate[0] * gyroRate[0] +
                                    gyroRate[1] * gyroRate[1] +
                                    gyroRate[2] * gyroRate[2]
                            ).toDouble()
                        } else {
                            0.0
                        },
                        hasGyro = hasGyroSample,
                        timestampSeconds = event.timestamp / 1_000_000_000.0
                    )
                )
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

    /**
     * Screen-right expressed in raw device coordinates, for the gyro
     * projection. Follows the same per-rotation remapping as
     * [screenUpInDeviceCoords] and [screenRemapAxes]: at ROTATION_0 the
     * screen-right axis is device X, and each further quarter turn rotates it
     * the same way the up axis rotates.
     */
    private fun screenRightInDeviceCoords(): FloatArray = when (displayRotation()) {
        Surface.ROTATION_90 -> floatArrayOf(0f, 1f, 0f)
        Surface.ROTATION_180 -> floatArrayOf(-1f, 0f, 0f)
        Surface.ROTATION_270 -> floatArrayOf(0f, -1f, 0f)
        else -> floatArrayOf(1f, 0f, 0f)
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
}

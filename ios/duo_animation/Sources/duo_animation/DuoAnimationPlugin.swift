import Flutter
import UIKit
import CoreMotion

/// Streams screen-axes orientation to Dart.
///
/// Attitude comes from `.xArbitraryZVertical`, the reference frame that leaves the
/// magnetometer out of the fusion. That is deliberate: the effect tracks how far the
/// screen has turned away from wherever the user was holding it, and magnetic heading
/// has nothing to do with that. Pulling in the compass would let a passing magnet or a
/// recalibration shift the pose the effect is measured against.
///
/// No filtering happens here. Each reading is reduced to screen axes and the rotation
/// rate is projected onto them, then handed to Dart, where calibration, latency
/// prediction, smoothing and drift washout live.
public class DuoAnimationPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

  private let motionManager = CMMotionManager()
  private var eventSink: FlutterEventSink?

  private static let methodChannelName = "dev.duoanimation/duo_animation"
  private static let eventChannelName = "dev.duoanimation/duo_animation/motion"

  /// 60 Hz. Fast enough that the low-pass in Dart has material to work with, slow
  /// enough not to spend battery on samples that never reach a frame.
  private static let updateInterval = 1.0 / 60.0

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = DuoAnimationPlugin()
    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    let eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: registrar.messenger()
    )
    eventChannel.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "metrics":
      result([
        "pixelsPerMillimeter": pixelsPerMillimeter(),
        "hasRotationSensor": motionManager.isDeviceMotionAvailable,
      ])
    case "stop":
      stopUpdates()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    guard motionManager.isDeviceMotionAvailable else {
      return FlutterError(
        code: "unavailable",
        message: "device motion is not available on this device",
        details: nil
      )
    }
    eventSink = events
    motionManager.deviceMotionUpdateInterval = DuoAnimationPlugin.updateInterval
    motionManager.startDeviceMotionUpdates(
      using: .xArbitraryZVertical,
      to: .main
    ) { [weak self] data, _ in
      guard let self = self, let data = data, let sink = self.eventSink else { return }
      sink(self.frame(from: data))
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stopUpdates()
    return nil
  }

  private func stopUpdates() {
    motionManager.stopDeviceMotionUpdates()
    eventSink = nil
  }

  /// Builds one 14 value frame: a row-major 3x3 whose columns are screen-right,
  /// screen-up and screen-normal, then the two projected rates, the rate magnitude,
  /// the gyro flag and the timestamp. Returned as typed data rather than a plain
  /// array; see the comment at the return site for why.
  private func frame(from data: CMDeviceMotion) -> FlutterStandardTypedData {
    let m = data.attitude.rotationMatrix
    let axes = screenAxesInDeviceSpace()

    let right = rotate(m, axes.right)
    let up = rotate(m, axes.up)
    let normal = cross(right, up)

    let rate = data.rotationRate
    let omegaScreenY = dot(rate, axes.up)
    let omegaScreenX = dot(rate, axes.right)
    let omegaMagnitude = (rate.x * rate.x + rate.y * rate.y + rate.z * rate.z).squareRoot()

    let values: [Double] = [
      right.0, up.0, normal.0,
      right.1, up.1, normal.1,
      right.2, up.2, normal.2,
      omegaScreenY,
      omegaScreenX,
      omegaMagnitude,
      1.0,
      data.timestamp,
    ]

    // The standard method codec only takes the float64 typed-data path for a value
    // that is explicitly typed as such. A plain Swift Array bridges to NSArray and
    // gets encoded element by element as a generic list instead, and the Dart side
    // decodes this channel by requiring Float64List, so a generic list is dropped
    // silently rather than read. Wrapping in FlutterStandardTypedData(float64:)
    // is what puts these bytes on the typed path.
    return FlutterStandardTypedData(
      float64: values.withUnsafeBufferPointer { Data(buffer: $0) }
    )
  }

  /// Screen-right and screen-up expressed in device coordinates for the current
  /// interface orientation. Device space is x to the right, y up and z out of the
  /// screen when the device is held upright in portrait.
  ///
  /// The landscape cases are the ones worth checking on hardware: which physical edge
  /// `landscapeLeft` refers to is a recurring source of inverted axes.
  private func screenAxesInDeviceSpace() -> (
    right: (Double, Double, Double),
    up: (Double, Double, Double)
  ) {
    switch interfaceOrientation() {
    case .landscapeLeft:
      return (right: (0, 1, 0), up: (-1, 0, 0))
    case .landscapeRight:
      return (right: (0, -1, 0), up: (1, 0, 0))
    case .portraitUpsideDown:
      return (right: (-1, 0, 0), up: (0, -1, 0))
    default:
      return (right: (1, 0, 0), up: (0, 1, 0))
    }
  }

  private func interfaceOrientation() -> UIInterfaceOrientation {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first
    return scene?.interfaceOrientation ?? .portrait
  }

  private func rotate(
    _ m: CMRotationMatrix,
    _ v: (Double, Double, Double)
  ) -> (Double, Double, Double) {
    return (
      m.m11 * v.0 + m.m12 * v.1 + m.m13 * v.2,
      m.m21 * v.0 + m.m22 * v.1 + m.m23 * v.2,
      m.m31 * v.0 + m.m32 * v.1 + m.m33 * v.2
    )
  }

  private func cross(
    _ a: (Double, Double, Double),
    _ b: (Double, Double, Double)
  ) -> (Double, Double, Double) {
    return (
      a.1 * b.2 - a.2 * b.1,
      a.2 * b.0 - a.0 * b.2,
      a.0 * b.1 - a.1 * b.0
    )
  }

  private func dot(_ rate: CMRotationRate, _ v: (Double, Double, Double)) -> Double {
    return rate.x * v.0 + rate.y * v.1 + rate.z * v.2
  }

  /// Physical pixels per millimetre.
  ///
  /// iOS exposes no DPI, so this uses the panel densities Apple has shipped for years,
  /// 163 points per inch on iPhone and 132 on iPad, scaled by the native scale factor.
  /// A caller who knows better can override the whole thing through
  /// `DuoFoldParameters.pixelsPerMillimeter`.
  private func pixelsPerMillimeter() -> Double {
    let pointsPerInch: Double = UIDevice.current.userInterfaceIdiom == .pad ? 132 : 163
    let scale = Double(screenScale())
    return pointsPerInch * scale / 25.4
  }

  private func screenScale() -> CGFloat {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first
    return scene?.screen.nativeScale ?? UIScreen.main.nativeScale
  }
}

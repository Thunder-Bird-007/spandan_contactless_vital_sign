import Foundation

/// Rolling time-windowed buffer of ROI-averaged RGB samples. Real, permanent
/// code -- bookkeeping only (drop samples older than the window), independent
/// of whichever algorithm consumes the buffer. Direct port of
/// android/app/.../signal/SignalBuffer.kt.
final class SignalBuffer {

    /// The single, tunable knob for how much wall-clock history the rolling
    /// buffer keeps. Kept at the same value the Android port settled on after
    /// its own on-device timing/window-length investigation (see
    /// android/README.md's "Window-length change: 10s -> 25s" section) --
    /// this iOS port has not repeated that investigation on real iPhone
    /// hardware (different camera/ISP throughput than the Android port's
    /// Galaxy A35), so 25s here is inherited, not independently re-verified.
    static let windowDurationSeconds: Double = 25.0

    private let windowSeconds: Double
    private var samples: [RgbSample] = []
    private let lock = NSLock()

    init(windowSeconds: Double = SignalBuffer.windowDurationSeconds) {
        self.windowSeconds = windowSeconds
    }

    func add(_ sample: RgbSample) {
        lock.lock()
        defer { lock.unlock() }
        samples.append(sample)
        let cutoffMs = sample.timestampMs - Int64(windowSeconds * 1000)
        while let first = samples.first, first.timestampMs < cutoffMs {
            samples.removeFirst()
        }
    }

    func snapshot() -> [RgbSample] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll()
    }
}

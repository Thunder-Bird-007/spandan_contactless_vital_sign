import Foundation
import XCTest
@testable import Spandan

/// Direct port of android/.../signal/MorphologyWaveformEstimatorTest.kt
/// (read directly, including its own Segment 31 continuousWaveform
/// additions, before writing this): exercises the full
/// MorphologyWaveformEstimator orchestration end to end on a SYNTHETIC
/// pulsatile RGB stream (no camera needed), since no physical device was
/// available this session to verify it any other way. Component-level
/// correctness of each stage is already covered by that stage's own test --
/// this test's job is to catch WIRING mistakes between them (wrong argument
/// order, a mismatched fs, an error that escapes the fail-soft layer) that
/// a component-level test can't see.
final class MorphologyWaveformEstimatorTests: XCTestCase {

    /// Builds a synthetic RGB stream at `fs` Hz for `durationSec` seconds,
    /// where each channel is `baseline * (1 + k * m(t))` -- k differs per
    /// channel (same asymmetry CHROM/POS rely on to isolate a pulse from a
    /// generic per-channel modulation), m(t) a two-harmonic pulsatile
    /// waveform at `f0`Hz plus small noise, roughly mimicking real ROI
    /// pixel-average scale/modulation depth.
    private func buildPulsatileSamples(fs: Double, durationSec: Double, f0: Double, startMs: Int64 = 0) -> [RgbSample] {
        let n = Int(fs * durationSec)
        var rng = SeededGenerator(seed: 99)
        return (0..<n).map { i in
            let t = Double(i) / fs
            let m = sin(2 * .pi * f0 * t) + 0.3 * sin(2 * .pi * 2 * f0 * t)
            let noise = (Double.random(in: 0..<1, using: &rng) - 0.5) * 0.01
            return RgbSample(
                timestampMs: startMs + Int64(t * 1000),
                red: Float(150.0 * (1.0 + 0.02 * m + noise)),
                green: Float(120.0 * (1.0 + 0.05 * m + noise)),
                blue: Float(100.0 * (1.0 + 0.03 * m + noise))
            )
        }
    }

    func testReturnsNilAndWarmingUpWithTooFewSamples() {
        let estimator = MorphologyWaveformEstimator()
        let samples = buildPulsatileSamples(fs: 20.0, durationSec: 1.0, f0: 1.2)
        let result = estimator.update(samples: samples)
        XCTAssertNil(result)
        XCTAssertEqual(estimator.lastStatus, .warmingUp)
    }

    func testProducesAWellFormedEstimateAtAGoodFrameRateWithWideBand() {
        let estimator = MorphologyWaveformEstimator()
        // fs=20Hz, Nyquist=10Hz -- comfortably admits the WIDE band (0.5-8Hz).
        let samples = buildPulsatileSamples(fs: 20.0, durationSec: 25.0, f0: 1.2)
        let result = estimator.update(samples: samples)

        XCTAssertNotNil(result, "expected a non-nil estimate at a good frame rate")
        guard let result else { return }
        XCTAssertEqual(estimator.lastStatus, .ok)
        XCTAssertEqual(result.bandModeUsed, .wide)
        XCTAssertEqual(result.waveform.count, 256)
        XCTAssertTrue(result.notchConfidence >= 0.0 && result.notchConfidence <= 1.0)
        XCTAssertTrue(result.notchConfidenceRaw >= 0.0)
        XCTAssertTrue(result.harmonicMethodUsed == "adaptiveHarmonic" || result.harmonicMethodUsed == "gaussian015")
        XCTAssertTrue(result.fs > 19.0 && result.fs < 21.0)
        for v in result.waveform { XCTAssertTrue(v.isFinite) }

        // continuousWaveform -- resampled.sigUniform (250Hz,
        // ResampleUniform.defaultTargetFs) tail-windowed to 8s, so a full
        // 25s window should yield exactly 250*8=2000 samples, not the
        // shorter 256-sample single-beat `waveform` above.
        XCTAssertEqual(result.continuousWaveform.count, 2000)
        for v in result.continuousWaveform { XCTAssertTrue(v.isFinite) }
    }

    func testContinuousWaveformIsTailWindowedNotTheWholeSignal() {
        let estimator = MorphologyWaveformEstimator()
        // A much longer window (60s) than the 8s continuousWaveform slice --
        // guards against a future regression that accidentally returns the
        // WHOLE resampled signal instead of the tail-windowed slice.
        let samples = buildPulsatileSamples(fs: 20.0, durationSec: 60.0, f0: 1.2)
        let result = estimator.update(samples: samples)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.continuousWaveform.count, 2000)
    }

    func testFallsBackToMidBandWhenWideIsNotAdmissible() {
        let estimator = MorphologyWaveformEstimator()
        // fs=14Hz, Nyquist=7Hz -- WIDE (needs <8) is inadmissible, MID (needs <6) is.
        let samples = buildPulsatileSamples(fs: 14.0, durationSec: 25.0, f0: 1.2)
        let result = estimator.update(samples: samples)

        XCTAssertNotNil(result, "expected a non-nil estimate at fs=14Hz via the MID fallback")
        XCTAssertEqual(result?.bandModeUsed, .mid)
        XCTAssertEqual(estimator.lastStatus, .ok)
    }

    func testSkipsTheWindowRatherThanCrashWhenFsIsTooLowForEitherBand() {
        let estimator = MorphologyWaveformEstimator()
        // fs=10Hz, Nyquist=5Hz -- too low for even MID (needs <6).
        let samples = buildPulsatileSamples(fs: 10.0, durationSec: 25.0, f0: 1.2)
        let result = estimator.update(samples: samples)

        XCTAssertNil(result)
        XCTAssertEqual(estimator.lastStatus, .lowSignalQuality)
    }

    func testNeverCrashesAcrossARangeOfRealisticFrameRates() {
        // Sweep across a plausible on-device fps range plus a couple of
        // values outside it -- the orchestrator must fail soft (nil +
        // lowSignalQuality) on every input, never crash, since this runs
        // live on uncontrolled camera data.
        for fs in [9.0, 11.0, 13.44, 16.0, 18.0, 21.4, 25.0, 30.0] {
            let estimator = MorphologyWaveformEstimator()
            let samples = buildPulsatileSamples(fs: fs, durationSec: 25.0, f0: 1.2)
            // No throw path in Swift here (this port uses Optionals, not
            // exceptions) -- the real assertion is just that this completes
            // without a runtime trap (force-unwrap crash, index out of
            // range, etc.), which XCTest would otherwise report as a fatal
            // error aborting the whole test run.
            _ = estimator.update(samples: samples)
        }
    }
}

/// Deterministic seeded RNG (a small linear congruential generator), so
/// `buildPulsatileSamples`'s synthetic noise is reproducible across runs --
/// Swift's `Double.random` needs an explicit `RandomNumberGenerator`, unlike
/// Kotlin's `kotlin.random.Random(seed)` which the Android port's own test
/// uses directly.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

import Foundation
import XCTest
@testable import Spandan

/// Mirrors android/.../signal/EnsembleAverageBeatsTest.kt's own approach:
/// a synthetic periodic pulse (asymmetric -- a fundamental plus a second
/// harmonic, like a real cardiac cycle, not a symmetric pure sine) at a
/// known rate should produce a well-formed Result with the expected number
/// of beats found and a finite prototype.
final class EnsembleAverageBeatsTests: XCTestCase {

    /// Builds `durationSec` seconds of a synthetic asymmetric periodic pulse
    /// at `fs` Hz and `f0` Hz -- an asymmetric cycle (unlike a pure sine)
    /// gives the systolic-peak-anchored time warp something real to do.
    private func buildPeriodicPulse(fs: Double, durationSec: Double, f0: Double) -> [Double] {
        let n = Int(fs * durationSec)
        return (0..<n).map { i in
            let t = Double(i) / fs
            return sin(2 * .pi * f0 * t) + 0.3 * sin(2 * .pi * 2 * f0 * t)
        }
    }

    func testProducesAWellFormedResultForATenSecondPulseTrain() {
        let fs = 100.0
        let f0 = 1.2 // ~72bpm -- 12 beats over 10s
        let sig = buildPeriodicPulse(fs: fs, durationSec: 10.0, f0: f0)

        let result = EnsembleAverageBeats.apply(sig, fs: fs)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.prototype.trimmedMean.count, 256)
        XCTAssertEqual(result!.prototype.median.count, 256)
        for v in result!.prototype.trimmedMean { XCTAssertTrue(v.isFinite) }
        XCTAssertGreaterThanOrEqual(result!.stats.beatsFound, 10) // ~12 expected, allow edge-crossing slack
        XCTAssertGreaterThan(result!.stats.beatsAveraged, 0)
        XCTAssertEqual(result!.beatMatrix.count, result!.stats.beatsAveraged)
    }

    func testReturnsNilWithTooFewBeats() {
        // Only ~2 cycles in a short window -- below the "need at least 3"
        // gate on negative-going zero crossings.
        let fs = 100.0
        let f0 = 1.2
        let sig = buildPeriodicPulse(fs: fs, durationSec: 1.5, f0: f0)
        XCTAssertNil(EnsembleAverageBeats.apply(sig, fs: fs))
    }

    func testCustomBeatSamplesOptionIsRespected() {
        let fs = 100.0
        let f0 = 1.2
        let sig = buildPeriodicPulse(fs: fs, durationSec: 10.0, f0: f0)
        var opts = EnsembleAverageBeats.Options()
        opts.beatSamples = 64
        let result = EnsembleAverageBeats.apply(sig, fs: fs, opts: opts)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.prototype.trimmedMean.count, 64)
    }
}

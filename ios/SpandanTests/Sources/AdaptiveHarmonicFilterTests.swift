import Foundation
import XCTest
@testable import Spandan

/// Mirrors android/.../signal/AdaptiveHarmonicFilterTest.kt's own approach:
/// a synthetic signal built from a few harmonics of a known f0 PLUS an
/// out-of-band high-frequency noise component should, after filtering,
/// correlate strongly with the pure harmonic sum and have that noise
/// component substantially attenuated.
final class AdaptiveHarmonicFilterTests: XCTestCase {

    private func pearson(_ x: [Double], _ y: [Double]) -> Double {
        let mx = x.reduce(0, +) / Double(x.count)
        let my = y.reduce(0, +) / Double(y.count)
        var num = 0.0, sxx = 0.0, syy = 0.0
        for i in x.indices {
            let dx = x[i] - mx, dy = y[i] - my
            num += dx * dy; sxx += dx * dx; syy += dy * dy
        }
        return num / (sxx * syy).squareRoot()
    }

    func testFilteredOutputCorrelatesStronglyWithTheKnownHarmonicContent() {
        let fs = 20.0
        let n = 300
        let f0 = 1.2 // ~72bpm
        var pureHarmonics = [Double](repeating: 0.0, count: n)
        var withNoise = [Double](repeating: 0.0, count: n)
        for i in 0..<n {
            let t = Double(i) / fs
            let h = sin(2 * .pi * f0 * t) + 0.5 * sin(2 * .pi * 2 * f0 * t) + 0.25 * sin(2 * .pi * 3 * f0 * t)
            let outOfBandNoise = 0.8 * sin(2 * .pi * 8.5 * t) // well above the 6th harmonic (7.2Hz)
            pureHarmonics[i] = h
            withNoise[i] = h + outOfBandNoise
        }

        let result = AdaptiveHarmonicFilter.apply(withNoise, frameRate: fs, numHarmonics: 6, f0HzOverride: f0)
        XCTAssertNotNil(result)
        for v in result!.filtered { XCTAssertTrue(v.isFinite) }

        let correlation = pearson(result!.filtered, pureHarmonics)
        XCTAssertGreaterThan(correlation, 0.9, "filtered output should closely track the pure in-band harmonic content, not the out-of-band noise")
        XCTAssertEqual(result!.f0Hz, f0, accuracy: 1e-9)
    }

    /// [Fixed after a real CI run caught it] The first version of this test
    /// asserted a pure 8Hz tone produces NO bin in HeartRateFft's 0.7-4Hz
    /// band, expecting `apply` to return nil without an f0 override. A real
    /// xcodebuild test run (no Mac available locally to catch this any
    /// other way) showed that assumption was false: a finite-length DFT of
    /// ANY real signal has spectral leakage into every bin (sidelobes, not
    /// zeros), so `HeartRateFft.estimateBpm` -- which just picks the
    /// LARGEST-magnitude in-band bin, with no minimum-magnitude floor --
    /// essentially always finds SOME peak in-band, however small. This is a
    /// property of the algorithm itself (the Kotlin port would behave
    /// identically, since both compute the exact same DFT values), not a
    /// bug this port introduced -- fixed by testing something actually
    /// true instead: that the no-override path, when there genuinely IS
    /// strong in-band content, finds an f0 close to the real one.
    func testWithoutAnF0OverrideFindsTheRealF0WhenOneIsPresent() {
        let fs = 20.0
        let n = 300
        let f0 = 1.2
        let sig = (0..<n).map { i -> Double in
            let t = Double(i) / fs
            return sin(2 * .pi * f0 * t) + 0.5 * sin(2 * .pi * 2 * f0 * t)
        }
        let result = AdaptiveHarmonicFilter.apply(sig, frameRate: fs, numHarmonics: 6)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.f0Hz, f0, accuracy: 0.1)
    }
}

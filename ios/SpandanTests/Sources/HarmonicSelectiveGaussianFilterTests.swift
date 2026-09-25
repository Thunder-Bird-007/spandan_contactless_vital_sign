import Foundation
import XCTest
@testable import Spandan

/// Same synthetic-signal approach as AdaptiveHarmonicFilterTests -- this
/// filter's Gaussian-tapered passbands should still isolate the in-band
/// harmonic content from out-of-band noise, just with soft (not hard) edges.
final class HarmonicSelectiveGaussianFilterTests: XCTestCase {

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
        let f0 = 1.2
        var pureHarmonics = [Double](repeating: 0.0, count: n)
        var withNoise = [Double](repeating: 0.0, count: n)
        for i in 0..<n {
            let t = Double(i) / fs
            let h = sin(2 * .pi * f0 * t) + 0.5 * sin(2 * .pi * 2 * f0 * t) + 0.25 * sin(2 * .pi * 3 * f0 * t)
            let outOfBandNoise = 0.8 * sin(2 * .pi * 8.5 * t)
            pureHarmonics[i] = h
            withNoise[i] = h + outOfBandNoise
        }

        let result = HarmonicSelectiveGaussianFilter.apply(withNoise, frameRate: fs, numHarmonics: 6, f0HzOverride: f0, alpha: 0.15)
        XCTAssertNotNil(result)
        for v in result!.filtered { XCTAssertTrue(v.isFinite) }

        let correlation = pearson(result!.filtered, pureHarmonics)
        XCTAssertGreaterThan(correlation, 0.85)
        XCTAssertEqual(result!.f0Hz, f0, accuracy: 1e-9)
    }

    func testReturnsNilForNonPositiveSigma() {
        // alpha*f0 <= 0 is guarded explicitly (sigma must be positive).
        let sig = (0..<100).map { Double($0) }
        XCTAssertNil(HarmonicSelectiveGaussianFilter.apply(sig, frameRate: 20.0, f0HzOverride: 1.0, alpha: 0.0))
    }
}

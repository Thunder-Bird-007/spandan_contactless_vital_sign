import Foundation
import XCTest
@testable import Spandan

/// Direct port of android/app/src/test/java/com/spandan/app/signal/
/// BandpassFilterTest.kt: feeds a synthetic sine at a known in-band frequency
/// (1.2Hz, ~72bpm) and a known out-of-band frequency (0.2Hz) through
/// BandpassFilter and confirms the in-band component survives with roughly
/// unity gain while the out-of-band component is substantially attenuated --
/// same "verify before trusting on real data" discipline as the Android port
/// and the MATLAB side's own Hoffman dataset sanity check.
final class BandpassFilterTests: XCTestCase {

    /// Quadrature (sine/cosine correlation) amplitude estimate of a single
    /// frequency component in `signal`, used only to score filter output -- not
    /// part of the shipped pipeline.
    private func sineAmplitude(_ signal: [Double], freqHz: Double, fs: Double) -> Double {
        var sumCos = 0.0
        var sumSin = 0.0
        for i in 0..<signal.count {
            let t = Double(i) / fs
            sumCos += signal[i] * cos(2 * Double.pi * freqHz * t)
            sumSin += signal[i] * sin(2 * Double.pi * freqHz * t)
        }
        return 2.0 / Double(signal.count) * (sumCos * sumCos + sumSin * sumSin).squareRoot()
    }

    func testInBandSinePassesWhileOutOfBandSineIsAttenuated() {
        let fs = 30.0
        let durationSeconds = 10.0
        let n = Int(fs * durationSeconds)

        let inBandHz = 1.2 // ~72 bpm, inside the 0.7-4Hz passband
        let outOfBandHz = 0.2 // well below the 0.7Hz low cutoff

        let input: [Double] = (0..<n).map { i in
            let t = Double(i) / fs
            return sin(2 * Double.pi * inBandHz * t) + sin(2 * Double.pi * outOfBandHz * t)
        }

        let output = BandpassFilter.apply(input, fs: fs)

        let inBandIn = sineAmplitude(input, freqHz: inBandHz, fs: fs)
        let outOfBandIn = sineAmplitude(input, freqHz: outOfBandHz, fs: fs)
        let inBandOut = sineAmplitude(output, freqHz: inBandHz, fs: fs)
        let outOfBandOut = sineAmplitude(output, freqHz: outOfBandHz, fs: fs)

        XCTAssertGreaterThan(inBandIn, 0.8, "amplitude estimator sanity check on raw input")
        XCTAssertGreaterThan(inBandOut, 0.5 * inBandIn, "in-band signal should pass with roughly unity gain")
        XCTAssertLessThan(outOfBandOut, 0.25 * outOfBandIn, "out-of-band signal should be substantially attenuated")
        XCTAssertGreaterThan(inBandOut, 3.0 * outOfBandOut, "in-band should dominate out-of-band after filtering")
    }
}

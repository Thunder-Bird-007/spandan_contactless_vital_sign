import Foundation
import XCTest
@testable import Spandan

final class HeartRateFftTests: XCTestCase {

    func testSyntheticSinePicksCorrectBpm() {
        let fs = 20.0
        let n = 500
        let trueBpm = 75.0
        let freqHz = trueBpm / 60.0

        let signal: [Double] = (0..<n).map { i in sin(2 * Double.pi * freqHz * Double(i) / fs) }

        guard let result = HeartRateFft.estimateBpm(signal, fs: fs) else {
            XCTFail("expected a result")
            return
        }

        let binWidthBpm = (fs / Double(n)) * 60.0
        XCTAssertEqual(
            result.bpm, trueBpm, accuracy: binWidthBpm,
            "peak bin should land within one FFT bin width of the true frequency"
        )
    }

    func testReturnsNilWhenBandIsEmpty() {
        // Too few samples / too low an fs for any bin to fall inside 0.7-4Hz.
        let result = HeartRateFft.estimateBpm([1.0, 2.0, 3.0, 4.0], fs: 1.0)
        XCTAssertNil(result)
    }
}

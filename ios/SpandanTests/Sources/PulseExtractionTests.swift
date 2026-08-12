import XCTest
@testable import Spandan

final class PulseExtractionTests: XCTestCase {

    func testSampleStdDevMatchesKnownValue() {
        // Classic worked example (N-1 sample standard deviation): std of
        // [2,4,4,4,5,5,7,9] = sqrt(32/7) ~= 2.13809.
        let values: [Double] = [2, 4, 4, 4, 5, 5, 7, 9]
        XCTAssertEqual(PulseExtraction.sampleStdDev(values), 2.13809, accuracy: 1e-4)
    }

    func testSampleStdDevOfConstantSignalIsZero() {
        XCTAssertEqual(PulseExtraction.sampleStdDev([Double](repeating: 5.0, count: 10)), 0.0, accuracy: 1e-9)
    }
}

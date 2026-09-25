import Foundation
import XCTest
@testable import Spandan

/// Direct port of android/.../signal/FixPolarityTest.kt's own approach:
/// a deliberately positive-skewed synthetic signal (mean above median, a
/// long right tail) should flip; its exact negation should not.
final class FixPolarityTests: XCTestCase {

    /// A signal with a long right tail (sparse large positive spikes on a
    /// flat baseline) -- positively skewed by construction.
    private func positivelySkewedSignal(count: Int) -> [Double] {
        (0..<count).map { i in i % 20 == 0 ? 5.0 : 0.0 }
    }

    func testReturnsNilForATooShortWindow() {
        // frameRate=20Hz, 5s of samples -- below the 10s minimum.
        let sig = positivelySkewedSignal(count: 100)
        XCTAssertNil(FixPolarity.apply(sig, frameRate: 20.0))
    }

    func testPositivelySkewedSignalGetsFlipped() {
        let sig = positivelySkewedSignal(count: 300) // 15s at 20Hz
        let result = FixPolarity.apply(sig, frameRate: 20.0)
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.skewValue, 0.0)
        XCTAssertTrue(result!.wasFlipped)
        for i in sig.indices {
            XCTAssertEqual(result!.oriented[i], -sig[i], accuracy: 1e-9)
        }
    }

    func testNegativelySkewedSignalIsNotFlipped() {
        let sig = positivelySkewedSignal(count: 300).map { -$0 } // long LEFT tail now
        let result = FixPolarity.apply(sig, frameRate: 20.0)
        XCTAssertNotNil(result)
        XCTAssertLessThan(result!.skewValue, 0.0)
        XCTAssertFalse(result!.wasFlipped)
        for i in sig.indices {
            XCTAssertEqual(result!.oriented[i], sig[i], accuracy: 1e-9)
        }
    }
}

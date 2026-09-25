import Foundation
import XCTest
@testable import Spandan

/// Direct port of android/.../signal/FixPolarityTest.kt's own approach.
///
/// [Fixed after a real CI run caught it] The first version of this file had
/// the flip direction backwards: `FixPolarity.apply`'s real rule (verified
/// against the Kotlin source both here and in FixPolarity.swift itself) is
/// `wasFlipped = skewValue < 0.0` -- i.e. a NEGATIVELY skewed (long LEFT
/// tail) signal gets flipped (negated, which makes it positively skewed
/// instead), while an ALREADY-positively-skewed signal is left alone. The
/// two tests below were originally asserting the opposite, and a real
/// on-CI xcodebuild test run (no Mac available locally to catch this any
/// other way) failed with exactly that mismatch -- fixed here, not in the
/// production code, since FixPolarity.swift's own logic already matched
/// the Kotlin source.
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

    func testPositivelySkewedSignalIsLeftAlone() {
        let sig = positivelySkewedSignal(count: 300) // 15s at 20Hz
        let result = FixPolarity.apply(sig, frameRate: 20.0)
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.skewValue, 0.0)
        XCTAssertFalse(result!.wasFlipped)
        for i in sig.indices {
            XCTAssertEqual(result!.oriented[i], sig[i], accuracy: 1e-9)
        }
    }

    func testNegativelySkewedSignalGetsFlipped() {
        let sig = positivelySkewedSignal(count: 300).map { -$0 } // long LEFT tail now
        let result = FixPolarity.apply(sig, frameRate: 20.0)
        XCTAssertNotNil(result)
        XCTAssertLessThan(result!.skewValue, 0.0)
        XCTAssertTrue(result!.wasFlipped)
        for i in sig.indices {
            XCTAssertEqual(result!.oriented[i], -sig[i], accuracy: 1e-9)
        }
    }
}

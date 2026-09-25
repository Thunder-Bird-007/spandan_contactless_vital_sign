import Foundation
import XCTest
@testable import Spandan

final class MorphologyBandpassFilterTests: XCTestCase {

    func testWideIsAdmissibleWellAboveItsOwnNyquistMargin() {
        XCTAssertTrue(MorphologyBandpassFilter.isAdmissible(fs: 20.0, mode: .wide)) // Nyquist=10Hz > 8Hz
    }

    func testWideIsNotAdmissibleNearNyquist() {
        XCTAssertFalse(MorphologyBandpassFilter.isAdmissible(fs: 15.0, mode: .wide)) // Nyquist=7.5Hz < 8Hz
    }

    func testMidIsAdmissibleWhereWideIsNot() {
        XCTAssertFalse(MorphologyBandpassFilter.isAdmissible(fs: 14.0, mode: .wide)) // Nyquist=7Hz < 8Hz
        XCTAssertTrue(MorphologyBandpassFilter.isAdmissible(fs: 14.0, mode: .mid))   // Nyquist=7Hz > 6Hz
    }

    func testPickPrefersWideWhenBothAreAdmissible() {
        XCTAssertEqual(pickIsWide(MorphologyBandpassFilter.pick(fs: 20.0)), true)
    }

    func testPickFallsBackToMidWhenWideIsNotAdmissible() {
        XCTAssertEqual(pickIsWide(MorphologyBandpassFilter.pick(fs: 14.0)), false)
    }

    func testPickReturnsNilWhenNeitherIsAdmissible() {
        XCTAssertNil(MorphologyBandpassFilter.pick(fs: 10.0)) // Nyquist=5Hz < 6Hz
    }

    func testApplyReturnsNilWhenModeIsNotAdmissible() {
        let sig = (0..<300).map { sin(2.0 * Double.pi * 1.2 * Double($0) / 15.0) }
        XCTAssertNil(MorphologyBandpassFilter.apply(sig, fs: 15.0, mode: .wide))
    }

    func testApplyProducesAFiniteResultWhenAdmissible() {
        let n = 300
        let fs = 20.0
        let sig = (0..<n).map { sin(2.0 * Double.pi * 1.2 * Double($0) / fs) }
        let result = MorphologyBandpassFilter.apply(sig, fs: fs, mode: .wide)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.filtered.count, n)
        for v in result!.filtered { XCTAssertTrue(v.isFinite) }
    }

    private func pickIsWide(_ mode: MorphologyBandpassFilter.BandMode?) -> Bool? {
        guard let mode else { return nil }
        return mode == .wide
    }
}

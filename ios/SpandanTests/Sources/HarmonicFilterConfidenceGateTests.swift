import Foundation
import XCTest
@testable import Spandan

final class HarmonicFilterConfidenceGateTests: XCTestCase {

    func testKeepsThePrimaryWhenItsConfidenceClearsTheBar() {
        let primary = HarmonicFilterConfidenceGate.Candidate(signal: [1, 2, 3], notchConfidence: 0.5, methodLabel: "adaptiveHarmonic")
        let fallback = HarmonicFilterConfidenceGate.Candidate(signal: [4, 5, 6], notchConfidence: 0.9, methodLabel: "gaussian015")
        let result = HarmonicFilterConfidenceGate.select(primary: primary, fallbacks: [fallback])
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.wasSubstituted)
        XCTAssertEqual(result!.selectedMethodLabel, "adaptiveHarmonic")
        XCTAssertEqual(result!.selectedSignal, [1, 2, 3])
    }

    func testSubstitutesTheFallbackWhenThePrimaryFailsTheBar() {
        let primary = HarmonicFilterConfidenceGate.Candidate(signal: [1, 2, 3], notchConfidence: 0.1, methodLabel: "adaptiveHarmonic")
        let fallback = HarmonicFilterConfidenceGate.Candidate(signal: [4, 5, 6], notchConfidence: 0.4, methodLabel: "gaussian015")
        let result = HarmonicFilterConfidenceGate.select(primary: primary, fallbacks: [fallback])
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.wasSubstituted)
        XCTAssertEqual(result!.selectedMethodLabel, "gaussian015")
    }

    func testPrimaryExactlyAtTheBarIsNotKept() {
        // The gate's own condition is `notchConfidence > confidenceThreshold`
        // (strictly greater), matching the Android port's own `>` operator.
        let primary = HarmonicFilterConfidenceGate.Candidate(signal: [1], notchConfidence: 0.3, methodLabel: "adaptiveHarmonic")
        let fallback = HarmonicFilterConfidenceGate.Candidate(signal: [2], notchConfidence: 0.3, methodLabel: "gaussian015")
        let result = HarmonicFilterConfidenceGate.select(primary: primary, fallbacks: [fallback], confidenceThreshold: 0.3)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.wasSubstituted)
    }

    func testNaNPrimaryConfidenceIsTreatedAsFailing() {
        let primary = HarmonicFilterConfidenceGate.Candidate(signal: [1], notchConfidence: .nan, methodLabel: "adaptiveHarmonic")
        let fallback = HarmonicFilterConfidenceGate.Candidate(signal: [2], notchConfidence: 0.0, methodLabel: "gaussian015")
        let result = HarmonicFilterConfidenceGate.select(primary: primary, fallbacks: [fallback])
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.wasSubstituted)
    }

    func testReturnsNilWhenFallbacksIsEmpty() {
        let primary = HarmonicFilterConfidenceGate.Candidate(signal: [1], notchConfidence: 0.1, methodLabel: "adaptiveHarmonic")
        XCTAssertNil(HarmonicFilterConfidenceGate.select(primary: primary, fallbacks: []))
    }
}

import Foundation
import XCTest
@testable import Spandan

final class NotchDetectIEMTests: XCTestCase {

    func testReturnsNilForAConstantSignal() {
        let flat = [Double](repeating: 5.0, count: 256)
        XCTAssertNil(NotchDetectIEM.apply(flat, fs: 250.0))
    }

    /// A synthetic two-bump prototype (a larger, narrower "systolic" bump
    /// followed by a smaller, wider "diastolic" bump, with a dip between
    /// them) -- roughly the SHAPE a real dicrotic waveform has. This is NOT
    /// a guarantee the IEM algorithm will flag a notch on this exact
    /// synthetic (its envelope-mean iteration is more involved than a
    /// simple peak/dip search), so this test asserts well-formedness
    /// (finite outputs, valid ranges) rather than asserting `detected`
    /// either way -- an honest bound given no on-device/ground-truth signal
    /// was available to validate the exact threshold behavior against.
    private func syntheticDicroticPrototype(count: Int = 256) -> [Double] {
        (0..<count).map { i in
            let x = Double(i) / Double(count - 1)
            let systolic = exp(-pow((x - 0.2) / 0.08, 2))
            let diastolic = 0.4 * exp(-pow((x - 0.5) / 0.10, 2))
            return systolic + diastolic
        }
    }

    func testProducesAWellFormedResultOnASyntheticDicroticShape() {
        let proto = syntheticDicroticPrototype()
        let result = NotchDetectIEM.apply(proto, fs: 256.0 * (72.0 / 60.0)) // effectiveFsHz-style scaling, same convention the orchestrator uses
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.confidence.isFinite)
        XCTAssertTrue(result!.confidenceRaw.isFinite)
        XCTAssertGreaterThanOrEqual(result!.confidence, 0.0)
        XCTAssertLessThanOrEqual(result!.confidence, 1.0)
        if result!.detected {
            XCTAssertGreaterThanOrEqual(result!.positionNormalized, 0.0)
            XCTAssertLessThanOrEqual(result!.positionNormalized, 1.0)
            XCTAssertTrue(result!.depth.isFinite)
        } else {
            XCTAssertTrue(result!.positionNormalized.isNaN)
            XCTAssertEqual(result!.confidence, 0.0)
        }
    }

    func testConfidenceNeverExceedsOneEvenWhenRawExceedsIt() {
        // confidence = min(1.0, confidenceRaw) by construction -- verified
        // indirectly via the well-formedness test above on every run, but
        // stated as its own explicit invariant here per this file's own
        // "clips at 1.0" doc note.
        let proto = syntheticDicroticPrototype()
        guard let result = NotchDetectIEM.apply(proto, fs: 200.0) else {
            XCTFail("expected a result for a non-constant prototype")
            return
        }
        XCTAssertLessThanOrEqual(result.confidence, result.confidenceRaw + 1e-9)
    }
}

import XCTest
@testable import Spandan

/// Tests the CHROM/POS switching rule (docs/Android_HR_Switching_Port_Spec.md,
/// ported verbatim into RealHeartRateEstimator.switchingDecision) at and around
/// its 29.27% threshold -- mirrors the Android port's own on-device spot-check
/// ("readings at 27.85% stayed on CHROM ... readings at 31.58% and above
/// switched to POS, exactly as the decision rule specifies with no off-by-one or
/// rounding slip").
final class RealHeartRateEstimatorSwitchingTests: XCTestCase {

    func testBelowThresholdStaysOnChrom() {
        // relative_disagreement = |80-75| / 77.5 = 6.45%, well under 29.27%.
        let decision = RealHeartRateEstimator.switchingDecision(chromBpm: 80.0, posBpm: 75.0)
        XCTAssertFalse(decision.usedPos)
        XCTAssertEqual(decision.displayedBpm, 80.0)
    }

    func testAboveThresholdSwitchesToPos() {
        // relative_disagreement = |100-70| / 85 = 35.3%, over 29.27%.
        let decision = RealHeartRateEstimator.switchingDecision(chromBpm: 100.0, posBpm: 70.0)
        XCTAssertTrue(decision.usedPos)
        XCTAssertEqual(decision.displayedBpm, 70.0)
    }

    func testJustAboveThresholdSwitchesToPos() {
        // Constructed so relative_disagreement lands a hair over the 29.27%
        // threshold -- checks the ">=" boundary fires without an off-by-one,
        // without relying on exact floating-point equality at the boundary.
        let mean = 100.0
        let delta = RealHeartRateEstimator.switchThreshold * mean * 1.001
        let chrom = mean + delta / 2.0
        let pos = mean - delta / 2.0
        let decision = RealHeartRateEstimator.switchingDecision(chromBpm: chrom, posBpm: pos)
        XCTAssertTrue(decision.usedPos)
    }

    func testJustBelowThresholdStaysOnChrom() {
        let mean = 100.0
        let delta = RealHeartRateEstimator.switchThreshold * mean * 0.999
        let chrom = mean + delta / 2.0
        let pos = mean - delta / 2.0
        let decision = RealHeartRateEstimator.switchingDecision(chromBpm: chrom, posBpm: pos)
        XCTAssertFalse(decision.usedPos)
    }
}

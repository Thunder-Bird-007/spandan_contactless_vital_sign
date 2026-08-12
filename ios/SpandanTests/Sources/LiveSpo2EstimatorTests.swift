import XCTest
@testable import Spandan

final class LiveSpo2EstimatorTests: XCTestCase {

    func testCalibrationMatchesAMinusBTimesR() {
        let r = 1.0
        let expected = LiveSpo2Estimator.calibrationA - LiveSpo2Estimator.calibrationB * r
        let actual = LiveSpo2Estimator.calibrate(ratioOfRatios: r)
        XCTAssertEqual(actual, expected, accuracy: 1e-9)

        // Sanity check for the sign-convention note this class's header flags:
        // with B negative, A - B*R must be GREATER than A as R increases from 0,
        // not less -- A - B*R != A + B*R when B is negative.
        XCTAssertGreaterThan(expected, LiveSpo2Estimator.calibrationA)
    }

    func testClampsToDisplayRange() {
        // calibrationB is negative, so calibrate() = A - B*R = A + |B|*R is
        // INCREASING in R -- a very negative R clamps to the 90% floor, a very
        // positive R clamps to the 100% ceiling.
        XCTAssertEqual(LiveSpo2Estimator.calibrate(ratioOfRatios: -1000.0), 90.0)
        XCTAssertEqual(LiveSpo2Estimator.calibrate(ratioOfRatios: 1000.0), 100.0)
    }
}

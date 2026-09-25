import XCTest
@testable import Spandan

final class PchipInterpolatorTests: XCTestCase {

    func testInterpolatingAtKnotsReturnsTheKnotValuesExactly() {
        let x: [Double] = [0, 1, 2, 3, 4]
        let y: [Double] = [0, 1.5, 0.5, 2.0, 1.0]
        let result = PchipInterpolator.interpolate(x, y, x)
        for i in x.indices {
            XCTAssertEqual(result[i], y[i], accuracy: 1e-9)
        }
    }

    func testLinearDataInterpolatesExactlyLinearly() {
        // A straight line has zero curvature everywhere -- PCHIP should
        // reproduce it exactly at any query point, not just at knots.
        let x: [Double] = [0, 1, 2, 3, 4, 5]
        let y: [Double] = x.map { 2.0 * $0 + 3.0 }
        let xq: [Double] = [0.5, 1.25, 2.75, 4.9]
        let result = PchipInterpolator.interpolate(x, y, xq)
        for (i, q) in xq.enumerated() {
            XCTAssertEqual(result[i], 2.0 * q + 3.0, accuracy: 1e-6)
        }
    }

    func testDoesNotOvershootBetweenAMonotonicStep() {
        // Shape-preservation is PCHIP's whole reason for existing here (see
        // this file's own doc) -- a monotonic input should never produce an
        // interpolated value outside the input's own min/max range.
        let x: [Double] = [0, 1, 2, 3]
        let y: [Double] = [0, 0, 10, 10]
        let xq = stride(from: 0.0, through: 3.0, by: 0.05).map { $0 }
        let result = PchipInterpolator.interpolate(x, y, xq)
        for v in result {
            XCTAssertGreaterThanOrEqual(v, -1e-9)
            XCTAssertLessThanOrEqual(v, 10.0 + 1e-9)
        }
    }

    func testQueryOutsideRangeClampsToNearestEndpoint() {
        let x: [Double] = [0, 1, 2]
        let y: [Double] = [5, 7, 9]
        let result = PchipInterpolator.interpolate(x, y, [-10, 10])
        XCTAssertEqual(result[0], 5.0, accuracy: 1e-9)
        XCTAssertEqual(result[1], 9.0, accuracy: 1e-9)
    }

    func testTwoKnotDegenerateCaseIsPlainLinearInterpolation() {
        let result = PchipInterpolator.interpolate([0, 2], [0, 10], [1])
        XCTAssertEqual(result[0], 5.0, accuracy: 1e-9)
    }
}

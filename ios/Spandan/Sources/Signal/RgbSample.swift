import Foundation

/// One spatially-averaged RGB reading from the ROI, at a point in time.
/// Direct port of android/app/.../signal/RgbSample.kt.
struct RgbSample {
    let timestampMs: Int64
    let red: Float
    let green: Float
    let blue: Float
}

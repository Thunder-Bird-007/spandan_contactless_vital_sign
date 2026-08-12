import CoreGraphics

/// Derives a forehead ROI (region of interest) as a fixed fractional sub-crop of a
/// detected face bounding box -- ported from android/app/.../camera/RoiCalculator.kt.
///
/// The four fractions are reconciled against MATLAB's validated geometry:
/// matlab/src/roi/extractROISignals.m's `computeRegionBBoxes`, default/original
/// `forehead` mode -- `clampedBBox(..., xFracLo=0.30, xFracHi=0.70, yFracLo=0.10,
/// yFracHi=0.30, ...)`. That is the exact geometry Segment 6's validated HR
/// pipeline (r=0.957) was run against, so this is a direct port of MATLAB's
/// numbers, not an independent iOS design choice -- same values the Android port
/// uses.
///
/// Works in this project's pixel-space convention: CGRect with origin top-left,
/// y increasing downward (matching Android's Rect(left, top, right, bottom)), NOT
/// UIKit/CoreGraphics' usual y-up convention -- see CoordinateMapper.swift and
/// FaceAnalyzer.swift for where that convention is established/converted.
enum RoiCalculator {

    private static let topFraction: CGFloat = 0.10
    private static let bottomFraction: CGFloat = 0.30
    private static let leftFraction: CGFloat = 0.30
    private static let rightFraction: CGFloat = 0.70

    static func foreheadRoi(from faceBox: CGRect) -> CGRect {
        let w = faceBox.width
        let h = faceBox.height
        let left = faceBox.minX + leftFraction * w
        let top = faceBox.minY + topFraction * h
        let right = faceBox.minX + rightFraction * w
        let bottom = faceBox.minY + bottomFraction * h
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}

import CoreVideo
import Foundation

/// Spatially averages R/G/B pixel intensities inside an ROI rect, sampled
/// directly from a bi-planar (NV12-style) `CVPixelBuffer` -- no `UIImage`/`CGImage`
/// round-trip needed. Ported from android/app/.../camera/RoiPixelAverager.kt.
///
/// Assumes `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange` (the format
/// CameraController explicitly requests): plane 0 is Y (1 byte/pixel), plane 1 is
/// interleaved Cb,Cr at half resolution in each dimension (2 bytes per 2x2 luma
/// block). This is iOS's bi-planar layout, different from Android's generic
/// 3-plane `YUV_420_888` (the Kotlin source indexes 3 separate Y/U/V planes) --
/// the BT.601 full-range YUV->RGB formula itself is identical and copied exactly.
enum RoiPixelAverager {

    // Skips every other pixel in each direction -- a performance knob, not a
    // signal-processing parameter, same as the Android port's SAMPLE_STRIDE.
    private static let sampleStride = 2

    static func averageRgb(pixelBuffer: CVPixelBuffer, roi: CGRect) -> RgbSample? {
        guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 2 else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard
            let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
            let uvBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
        else { return nil }

        let yStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        let yPtr = yBase.assumingMemoryBound(to: UInt8.self)
        let uvPtr = uvBase.assumingMemoryBound(to: UInt8.self)

        let left = max(0, min(width - 1, Int(roi.minX.rounded())))
        let top = max(0, min(height - 1, Int(roi.minY.rounded())))
        let right = max(left + 1, min(width, Int(roi.maxX.rounded())))
        let bottom = max(top + 1, min(height, Int(roi.maxY.rounded())))
        guard right > left, bottom > top else { return nil }

        var sumR = 0
        var sumG = 0
        var sumB = 0
        var count = 0

        var y = top
        while y < bottom {
            var x = left
            while x < right {
                let yIndex = y * yStride + x
                let uvRow = y / 2
                let uvCol = (x / 2) * 2 // interleaved Cb,Cr pair start
                let uvIndex = uvRow * uvStride + uvCol

                let yVal = Int(yPtr[yIndex])
                let uVal = Int(uvPtr[uvIndex]) - 128
                let vVal = Int(uvPtr[uvIndex + 1]) - 128

                // Standard BT.601 YUV -> RGB (same formula as the Android port).
                let r = Double(yVal) + 1.402 * Double(vVal)
                let g = Double(yVal) - 0.344136 * Double(uVal) - 0.714136 * Double(vVal)
                let b = Double(yVal) + 1.772 * Double(uVal)

                sumR += Int(min(255.0, max(0.0, r)))
                sumG += Int(min(255.0, max(0.0, g)))
                sumB += Int(min(255.0, max(0.0, b)))
                count += 1

                x += sampleStride
            }
            y += sampleStride
        }

        guard count > 0 else { return nil }
        return RgbSample(
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
            red: Float(sumR) / Float(count),
            green: Float(sumG) / Float(count),
            blue: Float(sumB) / Float(count)
        )
    }
}

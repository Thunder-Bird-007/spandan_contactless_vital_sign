import CoreVideo
import Foundation
import Vision

/// Result of analyzing one camera frame -- same shape as the Android port's
/// `FaceAnalysisResult` sealed class.
enum FaceAnalysisResult {
    case noFace
    case faceDetected(faceBox: CGRect, roiBox: CGRect, imageWidth: Int, imageHeight: Int, rgbSample: RgbSample?)
}

/// Runs Vision face detection on each live camera frame, derives the forehead
/// ROI, and spatially averages RGB inside it -- the iOS analog of
/// android/app/.../camera/FaceAnalyzer.kt (ML Kit there, Vision here; the ROI/
/// pixel-averaging orchestration is the same shape).
///
/// Reuses one `VNSequenceRequestHandler` across frames (cheaper than allocating
/// one per frame), mirroring the Android port's reused `FaceDetection` client.
/// `VNSequenceRequestHandler.perform` is synchronous for image-based requests, so
/// (unlike ML Kit's async listener API) this doesn't need a completion callback --
/// call sites just call `analyze(pixelBuffer:)` and get a result back directly.
final class FaceAnalyzer {

    private let requestHandler = VNSequenceRequestHandler()

    /// `orientation: .up` here relies on `CameraController` having already
    /// rotated the delivered pixel buffer to upright portrait via
    /// `AVCaptureConnection.videoOrientation` -- see that file's header comment.
    /// **This is this port's single highest-risk unverified assumption** (see
    /// ../README.md): if it's wrong, Vision will detect faces at the wrong
    /// apparent orientation and every downstream box will be off, the same class
    /// of bug the Android port found (and fixed) twice via real on-device
    /// logging before trusting its own coordinate math -- this port has not had
    /// that chance yet.
    func analyze(pixelBuffer: CVPixelBuffer) -> FaceAnalysisResult {
        let request = VNDetectFaceRectanglesRequest()
        do {
            try requestHandler.perform([request], on: pixelBuffer, orientation: .up)
        } catch {
            return .noFace
        }

        guard let observations = request.results, !observations.isEmpty else {
            return .noFace
        }

        // Always take the largest detected face, not the first -- same lesson
        // carried over from the MATLAB side (segment2) and the Android port,
        // where picking the first box instead of the largest caused a real
        // false-positive bug.
        guard let largest = observations.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) else {
            return .noFace
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let faceBox = Self.pixelRect(from: largest.boundingBox, imageWidth: width, imageHeight: height)
        let roiBox = RoiCalculator.foreheadRoi(from: faceBox)
        let rgbSample = RoiPixelAverager.averageRgb(pixelBuffer: pixelBuffer, roi: roiBox)

        return .faceDetected(faceBox: faceBox, roiBox: roiBox, imageWidth: width, imageHeight: height, rgbSample: rgbSample)
    }

    /// Vision's `boundingBox` is normalized [0,1] with origin bottom-left, y up
    /// (in the space of the orientation passed to the request -- `.up` here).
    /// Converts to this project's pixel-space convention (origin top-left, y
    /// down, matching Android's `Rect`) so RoiCalculator/RoiPixelAverager/
    /// CoordinateMapper can share one convention throughout.
    private static func pixelRect(from normalized: CGRect, imageWidth: Int, imageHeight: Int) -> CGRect {
        let w = CGFloat(imageWidth)
        let h = CGFloat(imageHeight)
        let x = normalized.minX * w
        let width = normalized.width * w
        let height = normalized.height * h
        let y = (1.0 - normalized.maxY) * h // flip: Vision's top edge is (1 - maxY) from the image top
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

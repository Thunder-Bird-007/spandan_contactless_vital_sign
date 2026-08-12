import CoreGraphics

/// Maps a rect from the live-analysis pixel-buffer's coordinate space into
/// on-screen view pixel coordinates, matching an AVCaptureVideoPreviewLayer using
/// `videoGravity = .resizeAspect` (uniform scale, letterboxed, never cropped --
/// the AVFoundation equivalent of Android's PreviewView ScaleType.FIT_CENTER) plus
/// the horizontal mirror a front camera's preview shows the user.
///
/// This is the ONE coordinate-space conversion this port needs, unlike the
/// Android port's two (`rotatedRectToSensorRect` + `rotatedRectToViewRect`) -- see
/// CameraController.swift's own header comment for why: this port pre-rotates the
/// live pixel buffer to upright portrait via `AVCaptureConnection.videoOrientation`,
/// so the face box, ROI box, and pixel-averaging all already share one coordinate
/// space (the pre-rotated buffer's own pixel grid); only the final on-screen
/// overlay placement needs a mapping, done here.
///
/// **Not verified on a physical device** (see ../README.md) -- ported from
/// android/app/.../camera/CoordinateMapper.kt's `rotatedRectToViewRect`, whose own
/// math WAS verified on a real device and needed no fix (the two real bugs the
/// Android port found were in the OTHER function, the sensor-space one this port
/// doesn't need). The math below is the same, but "same math, unverified inputs"
/// is still unverified -- confirm the overlay actually lines up with a real face
/// on a real iPhone before trusting it.
enum CoordinateMapper {

    static func viewRect(
        from rect: CGRect,
        imageWidth: Int,
        imageHeight: Int,
        viewWidth: CGFloat,
        viewHeight: CGFloat,
        isFrontCamera: Bool
    ) -> CGRect {
        let srcWidth = CGFloat(imageWidth)
        let srcHeight = CGFloat(imageHeight)
        guard srcWidth > 0, srcHeight > 0, viewWidth > 0, viewHeight > 0 else { return .zero }

        let scale = min(viewWidth / srcWidth, viewHeight / srcHeight)
        let offsetX = (viewWidth - srcWidth * scale) / 2
        let offsetY = (viewHeight - srcHeight * scale) / 2

        if isFrontCamera {
            let left = offsetX + (srcWidth - rect.maxX) * scale
            let right = offsetX + (srcWidth - rect.minX) * scale
            let top = offsetY + rect.minY * scale
            let bottom = offsetY + rect.maxY * scale
            return CGRect(x: left, y: top, width: right - left, height: bottom - top)
        } else {
            let left = offsetX + rect.minX * scale
            let top = offsetY + rect.minY * scale
            return CGRect(x: left, y: top, width: rect.width * scale, height: rect.height * scale)
        }
    }
}

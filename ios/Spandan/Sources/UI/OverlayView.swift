import UIKit

/// Draws the live face-detection box and the smaller ROI sub-box on top of the
/// camera preview. Coordinates are expected to already be in this view's own
/// point space (see CoordinateMapper.viewRect) -- this class only draws, it
/// doesn't do any coordinate math itself. Ported from
/// android/app/.../ui/OverlayView.kt.
final class OverlayView: UIView {

    private var faceRect: CGRect?
    private var roiRect: CGRect?

    private let faceColor = UIColor(red: 0x4C / 255, green: 0xAF / 255, blue: 0x50 / 255, alpha: 1) // green
    private let roiColor = UIColor(red: 0xFF / 255, green: 0xEB / 255, blue: 0x3B / 255, alpha: 1) // yellow

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
    }

    /// Pass nil for both to clear the overlay (e.g. when no face is found).
    func update(face: CGRect?, roi: CGRect?) {
        faceRect = face
        roiRect = roi
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        if let face = faceRect {
            ctx.setStrokeColor(faceColor.cgColor)
            ctx.setLineWidth(2.5)
            ctx.stroke(face)
        }
        if let roi = roiRect {
            ctx.setStrokeColor(roiColor.cgColor)
            ctx.setLineWidth(2.0)
            ctx.stroke(roi)
        }
    }
}

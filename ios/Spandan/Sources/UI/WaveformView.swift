import UIKit

/// Draws Branch 2's own filtered pulse trace -- the iOS analog of
/// android/app/.../ui/WaveformView.kt (read directly before writing this,
/// including its Segment 31 revision to a multi-cycle trace -- see below).
/// Same "no external chart library" choice this project has made elsewhere.
///
/// Renders `MorphologyWaveformEstimator.Estimate.continuousWaveform` (the
/// last several seconds of Branch 2's continuous, polarity-corrected pulse,
/// real Branch 2 output, typically several real cardiac cycles), NOT the
/// single ensemble-averaged beat -- mirroring the Android port's own
/// Segment 31 change (user feedback there: a single averaged beat did not
/// read as "live," wanted something closer to an actual clinical PPG
/// monitor's continuously refreshing multi-cycle trace). No per-beat notch
/// marker is drawn here either, for the same reason as the Android port: a
/// single marker position doesn't map cleanly onto a multi-cycle trace.
///
/// Rendering: a gradient area-fill under the line (`CAGradientLayer`,
/// masked to the line's own fill path, built lazily in `layoutSubviews`
/// since it needs real pixel dimensions), and the line itself is a smoothed
/// curve (quadratic Bezier through each segment's own midpoint) instead of
/// straight line segments.
final class WaveformView: UIView {

    private var values: [Double] = []

    private let backgroundColorValue = UIColor(red: 0x16 / 255, green: 0x16 / 255, blue: 0x16 / 255, alpha: 1)
    private let lineColor = UIColor(red: 0x7C / 255, green: 0x4D / 255, blue: 0xFF / 255, alpha: 1) // same purple as the Android port's accent_branch2
    private let gridColor = UIColor.white.withAlphaComponent(0.2)

    private let fillLayer = CAGradientLayer()
    private let fillMask = CAShapeLayer()
    private let lineLayer = CAShapeLayer()
    private let gridLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        layer.cornerRadius = 12
        layer.masksToBounds = true

        fillLayer.colors = [
            lineColor.withAlphaComponent(0.30).cgColor,
            lineColor.withAlphaComponent(0.0).cgColor
        ]
        fillLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        fillLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        fillLayer.mask = fillMask
        layer.addSublayer(fillLayer)

        lineLayer.fillColor = UIColor.clear.cgColor
        lineLayer.strokeColor = lineColor.cgColor
        lineLayer.lineWidth = 2.0
        lineLayer.lineCap = .round
        lineLayer.lineJoin = .round
        layer.addSublayer(lineLayer)

        gridLayer.strokeColor = gridColor.cgColor
        gridLayer.lineWidth = 1.0
        layer.addSublayer(gridLayer)
    }

    /// `continuousWaveform` is `MorphologyWaveformEstimator.Estimate.continuousWaveform`
    /// -- see this class's own doc for why that field, not the single-beat
    /// `waveform`, is what this view draws.
    func update(_ continuousWaveform: [Double]?) {
        values = continuousWaveform ?? []
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fillLayer.frame = bounds
        redraw()
    }

    private func redraw() {
        let points = values
        guard points.count >= 2, bounds.width > 0, bounds.height > 0 else {
            lineLayer.path = nil
            fillMask.path = nil
            gridLayer.path = nil
            return
        }

        // Faint horizontal midline -- a reference for "is this part of the
        // trace above or below the mean."
        let gridPath = UIBezierPath()
        gridPath.move(to: CGPoint(x: 0, y: bounds.height / 2))
        gridPath.addLine(to: CGPoint(x: bounds.width, y: bounds.height / 2))
        gridLayer.path = gridPath.cgPath

        let minV = points.min()!
        let maxV = points.max()!
        let range = max(maxV - minV, 1e-6)
        let stepX = bounds.width / CGFloat(points.count - 1)

        func point(_ i: Int) -> CGPoint {
            let x = CGFloat(i) * stepX
            let normalized = CGFloat((points[i] - minV) / range)
            let y = bounds.height - normalized * bounds.height
            return CGPoint(x: x, y: y)
        }

        // Smoothed curve: a quadratic Bezier through each segment's own
        // midpoint (a standard cheap smoothing trick -- NOT a signal-
        // processing change, this NEVER touches the underlying `values`
        // data, only how the same points are connected visually).
        let linePath = UIBezierPath()
        linePath.move(to: point(0))
        for i in 1..<points.count {
            let p0 = point(i - 1)
            let p1 = point(i)
            let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
            linePath.addQuadCurve(to: mid, controlPoint: p0)
        }
        linePath.addLine(to: point(points.count - 1))
        lineLayer.path = linePath.cgPath

        let fillPath = (linePath.copy() as! UIBezierPath)
        fillPath.addLine(to: CGPoint(x: point(points.count - 1).x, y: bounds.height))
        fillPath.addLine(to: CGPoint(x: point(0).x, y: bounds.height))
        fillPath.close()
        fillMask.path = fillPath.cgPath
    }

    override func draw(_ rect: CGRect) {
        // The background fill itself stays a plain draw (not a layer) so
        // the rounded corners (layer.cornerRadius above) clip it cleanly.
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setFillColor(backgroundColorValue.cgColor)
        ctx.fill(rect)
    }
}

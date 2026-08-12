import UIKit

/// Minimal scrolling line chart of the raw buffered green-channel signal. No
/// external chart library -- a plain Core Graphics draw, same as the Android
/// port's plain-Canvas `SignalChartView.kt`. Auto-scales Y to the current
/// buffer's min/max each frame (a *shape* sanity check, not a calibrated
/// amplitude reading).
final class SignalChartView: UIView {

    private var values: [Float] = []

    private let backgroundColorValue = UIColor(red: 0x14 / 255, green: 0x14 / 255, blue: 0x14 / 255, alpha: 1)
    private let lineColor = UIColor(red: 0x00 / 255, green: 0xC8 / 255, blue: 0x53 / 255, alpha: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
    }

    func updateValues(_ newValues: [Float]) {
        values = newValues
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setFillColor(backgroundColorValue.cgColor)
        ctx.fill(rect)

        let points = values
        guard points.count >= 2, bounds.width > 0, bounds.height > 0 else { return }

        let minV = points.min()!
        let maxV = points.max()!
        let range = max(maxV - minV, 1e-3)

        let path = UIBezierPath()
        let stepX = bounds.width / CGFloat(points.count - 1)
        for (i, v) in points.enumerated() {
            let x = CGFloat(i) * stepX
            let normalized = CGFloat((v - minV) / range)
            let y = bounds.height - normalized * bounds.height
            let point = CGPoint(x: x, y: y)
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        lineColor.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}

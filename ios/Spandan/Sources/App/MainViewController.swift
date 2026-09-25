import AVFoundation
import UIKit

/// Single-screen glue: camera lifecycle, permission handling, and wiring the
/// real analysis pipeline into the UI -- the iOS analog of MainActivity.kt.
/// HR is a real, validated CHROM/POS+FFT port (see
/// Signal/RealHeartRateEstimator.swift). SpO2 is a real ratio-of-ratios +
/// linear-calibration estimate (see Signal/LiveSpo2Estimator.swift), added
/// purely additively alongside HR. Branch 2 (waveform morphology / dicrotic
/// notch, see Signal/MorphologyWaveformEstimator.swift) runs independently
/// alongside both -- all three read the same `signalBuffer` snapshot,
/// none reads or modifies another's state.
///
/// UI structure mirrors android/app/.../MainActivity.kt + activity_main.xml
/// as of that port's own Segment 31: camera preview (with a bottom scrim)
/// -> ONE primary "LIVE SIGNAL" hero card (Branch 2's multi-cycle
/// continuous pulse trace, not the raw unfiltered chart the OLD version of
/// this file showed) -> a vitals card (HR/SpO2, with small tinted icons).
final class MainViewController: UIViewController {

    private let previewContainer = UIView()
    private let overlayView = OverlayView()
    private let previewScrim = CAGradientLayer()

    private let liveSignalCard = UIView()
    private let waveformView = WaveformView()
    private let branch2StatusLabel = UILabel()

    private let hrValueLabel = UILabel()
    private let spo2ValueLabel = UILabel()
    private let permissionDeniedView = UIView()
    private let permissionRationaleLabel = UILabel()
    private let grantPermissionButton = UIButton(type: .system)

    private let cameraController = CameraController()
    private let signalBuffer = SignalBuffer(windowSeconds: SignalBuffer.windowDurationSeconds)
    private let heartRateEstimator = RealHeartRateEstimator()
    private let spo2Estimator = LiveSpo2Estimator()
    private let morphologyEstimator = MorphologyWaveformEstimator()

    private var refreshTimer: Timer?

    // Tracks the permission state as of the last time we actually acted on it, so
    // viewWillAppear can tell "still the same state" apart from "changed while
    // backgrounded" -- see evaluatePermissionAndStart() below, same reasoning as
    // MainActivity's permissionGrantedLastKnown / onResume().
    private var permissionGrantedLastKnown = false

    // MARK: - Palette (mirrors android/app/.../res/values/colors.xml's own
    // small, deliberately limited palette additions from that port's own
    // Segment 31 -- same colors, so a screenshot of either app reads as one
    // system).
    private enum Palette {
        static let bgRoot = UIColor.black
        static let surfaceCard = UIColor(red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255, alpha: 0.80)
        static let surfaceCardTop = UIColor(red: 0x16 / 255, green: 0x16 / 255, blue: 0x16 / 255, alpha: 0.85)
        static let cardBorder = UIColor.white.withAlphaComponent(0.2)
        static let accentBranch2 = UIColor(red: 0x7C / 255, green: 0x4D / 255, blue: 0xFF / 255, alpha: 1)
        static let accentBranch2Border = UIColor(red: 0x7C / 255, green: 0x4D / 255, blue: 0xFF / 255, alpha: 0.30)
        static let accentHr = UIColor(red: 0xFF / 255, green: 0x6B / 255, blue: 0x81 / 255, alpha: 1)
        static let accentSpo2 = UIColor(red: 0x29 / 255, green: 0xB6 / 255, blue: 0xF6 / 255, alpha: 1)
        static let textPrimary = UIColor.white
        static let textSecondary = UIColor.white.withAlphaComponent(0.7)
        static let textTertiary = UIColor.white.withAlphaComponent(0.5)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.bgRoot
        buildLayout()

        previewContainer.layer.addSublayer(cameraController.previewLayer)
        cameraController.onResult = { [weak self] result in
            DispatchQueue.main.async { self?.handle(result: result) }
        }
        grantPermissionButton.addTarget(self, action: #selector(grantPermissionTapped), for: .touchUpInside)

        startUiRefreshLoop()
        evaluatePermissionAndStart(isInitial: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cameraController.previewLayer.frame = previewContainer.bounds
        previewScrim.frame = CGRect(x: 0, y: previewContainer.bounds.height - 64, width: previewContainer.bounds.width, height: 64)
    }

    // Re-checks camera permission every time the view (re)appears, not just once
    // at load -- without this, a user who denies the permission, backgrounds the
    // app, grants it via system Settings, and returns would stay stuck on the
    // "permission denied" screen. Compares against `permissionGrantedLastKnown`
    // rather than unconditionally acting every appearance, same reasoning as
    // MainActivity.onResume()'s own KDoc.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        evaluatePermissionAndStart(isInitial: false)
    }

    private func evaluatePermissionAndStart(isInitial: Bool) {
        switch cameraController.currentPermissionState() {
        case .granted:
            guard isInitial || !permissionGrantedLastKnown else { return }
            permissionGrantedLastKnown = true
            showPermissionDenied(false)
            cameraController.start()

        case .denied:
            guard isInitial || permissionGrantedLastKnown else { return }
            permissionGrantedLastKnown = false
            cameraController.stop()
            showPermissionDenied(true)

        case .notDetermined:
            cameraController.requestPermission { [weak self] granted in
                self?.permissionGrantedLastKnown = granted
                if granted {
                    self?.showPermissionDenied(false)
                    self?.cameraController.start()
                } else {
                    self?.showPermissionDenied(true)
                }
            }
        }
    }

    @objc private func grantPermissionTapped() {
        // iOS cannot re-prompt the system dialog after an explicit deny (the same
        // "USER_FIXED"-style caveat the Android port's own README notes) -- if
        // already denied, deep-link to Settings instead, matching what the system
        // itself tells the user to do in that state.
        if cameraController.currentPermissionState() == .denied {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            return
        }
        cameraController.requestPermission { [weak self] granted in
            self?.permissionGrantedLastKnown = granted
            if granted {
                self?.showPermissionDenied(false)
                self?.cameraController.start()
            } else {
                self?.showPermissionDenied(true)
            }
        }
    }

    private func showPermissionDenied(_ show: Bool) {
        permissionDeniedView.isHidden = !show
    }

    private func handle(result: FaceAnalysisResult) {
        switch result {
        case .noFace:
            overlayView.update(face: nil, roi: nil)

        case .faceDetected(let faceBox, let roiBox, let imageWidth, let imageHeight, let rgbSample):
            let viewSize = previewContainer.bounds.size
            let faceView = CoordinateMapper.viewRect(
                from: faceBox, imageWidth: imageWidth, imageHeight: imageHeight,
                viewWidth: viewSize.width, viewHeight: viewSize.height, isFrontCamera: true
            )
            let roiView = CoordinateMapper.viewRect(
                from: roiBox, imageWidth: imageWidth, imageHeight: imageHeight,
                viewWidth: viewSize.width, viewHeight: viewSize.height, isFrontCamera: true
            )
            overlayView.update(face: faceView, roi: roiView)

            if let sample = rgbSample {
                signalBuffer.add(sample)
            }
        }
    }

    /// Periodically refreshes the live signal + HR/SpO2 text, decoupled from
    /// the camera analysis frame rate -- same 200ms cadence as
    /// MainActivity's startUiRefreshLoop().
    private func startUiRefreshLoop() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.refreshUi()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func refreshUi() {
        let samples = signalBuffer.snapshot()

        // HR: real pipeline (detrend -> bandpass -> CHROM/POS -> FFT +
        // switching rule), see Signal/RealHeartRateEstimator.swift.
        if let hr = heartRateEstimator.update(samples: samples) {
            hrValueLabel.text = String(format: "%.0f bpm", hr)
        } else {
            hrValueLabel.text = "-- bpm"
        }

        // SpO2: real ratio-of-ratios + linear calibration, see
        // Signal/LiveSpo2Estimator.swift. Independent call on the same
        // samples snapshot -- does not read heartRateEstimator's state or
        // vice versa.
        if let spo2 = spo2Estimator.update(samples: samples) {
            spo2ValueLabel.text = String(format: "%.2f%%", spo2)
        } else {
            spo2ValueLabel.text = "-- %"
        }

        // Branch 2 -- independent call on the same samples snapshot (does
        // not read heartRateEstimator/spo2Estimator state or vice versa,
        // matching Branch 1/Branch 2's deliberate separation). Renders the
        // multi-cycle continuous trace, not the single averaged beat -- see
        // WaveformView's own doc.
        let morphologyEstimate = morphologyEstimator.update(samples: samples)
        waveformView.update(morphologyEstimate?.continuousWaveform)
        applyBranch2Status(morphologyEstimator.lastStatus, morphologyEstimate)
    }

    private func applyBranch2Status(_ status: EstimatorStatus, _ estimate: MorphologyWaveformEstimator.Estimate?) {
        switch status {
        case .warmingUp:
            branch2StatusLabel.text = "Warming up…"
            branch2StatusLabel.textColor = Palette.textSecondary
        case .lowSignalQuality:
            branch2StatusLabel.text = "Low signal quality"
            branch2StatusLabel.textColor = UIColor(red: 0xFF / 255, green: 0x70 / 255, blue: 0x43 / 255, alpha: 1)
        case .ok:
            guard let estimate else {
                branch2StatusLabel.text = "Warming up…"
                branch2StatusLabel.textColor = Palette.textSecondary
                return
            }
            let methodLabel = estimate.harmonicMethodUsed == "gaussian015" ? "Gaussian (α=0.15)" : "ABPF comb"
            if estimate.notchDetected {
                branch2StatusLabel.text = String(format: "%@ · conf %.2f", methodLabel, estimate.notchConfidenceRaw)
                branch2StatusLabel.textColor = estimate.notchConfidenceRaw > 0.3 ? UIColor(red: 0x4C / 255, green: 0xAF / 255, blue: 0x50 / 255, alpha: 1) : UIColor(red: 0xFF / 255, green: 0x70 / 255, blue: 0x43 / 255, alpha: 1)
            } else {
                branch2StatusLabel.text = "No notch detected this window"
                branch2StatusLabel.textColor = UIColor(red: 0xFF / 255, green: 0x70 / 255, blue: 0x43 / 255, alpha: 1)
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    // MARK: - Layout (programmatic, mirrors activity_main.xml's post-
    // Segment-31 structure: camera preview + overlays -> "LIVE SIGNAL" hero
    // card (Branch 2) -> vitals card).

    private func buildLayout() {
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.backgroundColor = .black

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(overlayView)

        previewScrim.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.7).cgColor]
        previewScrim.startPoint = CGPoint(x: 0.5, y: 0.0)
        previewScrim.endPoint = CGPoint(x: 0.5, y: 1.0)
        previewContainer.layer.addSublayer(previewScrim)

        permissionDeniedView.translatesAutoresizingMaskIntoConstraints = false
        permissionDeniedView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        permissionDeniedView.isHidden = true
        previewContainer.addSubview(permissionDeniedView)

        permissionRationaleLabel.text = "Camera access is needed to capture your face for heart-rate and SpO2 estimation. No video is stored or sent anywhere."
        permissionRationaleLabel.textColor = .white
        permissionRationaleLabel.font = .systemFont(ofSize: 16)
        permissionRationaleLabel.textAlignment = .center
        permissionRationaleLabel.numberOfLines = 0

        grantPermissionButton.setTitle("Grant camera permission", for: .normal)
        grantPermissionButton.tintColor = .white

        let permissionStack = UIStackView(arrangedSubviews: [permissionRationaleLabel, grantPermissionButton])
        permissionStack.axis = .vertical
        permissionStack.spacing = 16
        permissionStack.alignment = .center
        permissionStack.translatesAutoresizingMaskIntoConstraints = false
        permissionDeniedView.addSubview(permissionStack)

        // --- "LIVE SIGNAL" hero card (Branch 2) ---
        liveSignalCard.translatesAutoresizingMaskIntoConstraints = false
        liveSignalCard.backgroundColor = Palette.surfaceCardTop
        liveSignalCard.layer.cornerRadius = 22
        liveSignalCard.layer.borderWidth = 1
        liveSignalCard.layer.borderColor = Palette.accentBranch2Border.cgColor

        let liveSignalTitle = UILabel()
        liveSignalTitle.text = "LIVE SIGNAL"
        liveSignalTitle.textColor = Palette.textPrimary
        liveSignalTitle.font = .boldSystemFont(ofSize: 14)

        let liveSignalSubtitle = UILabel()
        liveSignalSubtitle.text = "Branch 2 · filtered pulse trace"
        liveSignalSubtitle.textColor = Palette.textTertiary
        liveSignalSubtitle.font = .systemFont(ofSize: 11)

        waveformView.translatesAutoresizingMaskIntoConstraints = false

        branch2StatusLabel.text = "Warming up…"
        branch2StatusLabel.textColor = Palette.textSecondary
        branch2StatusLabel.font = .systemFont(ofSize: 12)

        let liveSignalStack = UIStackView(arrangedSubviews: [liveSignalTitle, liveSignalSubtitle, waveformView, branch2StatusLabel])
        liveSignalStack.axis = .vertical
        liveSignalStack.spacing = 4
        liveSignalStack.setCustomSpacing(8, after: liveSignalSubtitle)
        liveSignalStack.setCustomSpacing(10, after: waveformView)
        liveSignalStack.translatesAutoresizingMaskIntoConstraints = false
        liveSignalCard.addSubview(liveSignalStack)

        // --- Vitals card (HR / SpO2) ---
        let vitalsCard = UIView()
        vitalsCard.translatesAutoresizingMaskIntoConstraints = false
        vitalsCard.backgroundColor = Palette.surfaceCardTop
        vitalsCard.layer.cornerRadius = 22
        vitalsCard.layer.borderWidth = 1
        vitalsCard.layer.borderColor = Palette.cardBorder.cgColor

        let hrColumn = makeVitalsColumn(iconName: "heart.fill", iconTint: Palette.accentHr, caption: "HEART RATE", valueLabel: hrValueLabel, placeholder: "-- bpm")
        let spo2Column = makeVitalsColumn(iconName: "drop.fill", iconTint: Palette.accentSpo2, caption: "BLOOD OXYGEN", valueLabel: spo2ValueLabel, placeholder: "-- %")

        let divider = UIView()
        divider.backgroundColor = Palette.cardBorder
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true

        let vitalsRow = UIStackView(arrangedSubviews: [hrColumn, divider, spo2Column])
        vitalsRow.axis = .horizontal
        vitalsRow.distribution = .fill
        vitalsRow.alignment = .fill
        vitalsRow.spacing = 16
        vitalsRow.translatesAutoresizingMaskIntoConstraints = false
        vitalsCard.addSubview(vitalsRow)

        view.addSubview(previewContainer)
        view.addSubview(liveSignalCard)
        view.addSubview(vitalsCard)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            previewContainer.topAnchor.constraint(equalTo: guide.topAnchor),
            previewContainer.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            previewContainer.trailingAnchor.constraint(equalTo: guide.trailingAnchor),

            overlayView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),

            permissionDeniedView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            permissionDeniedView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            permissionDeniedView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            permissionDeniedView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),

            permissionStack.centerXAnchor.constraint(equalTo: permissionDeniedView.centerXAnchor),
            permissionStack.centerYAnchor.constraint(equalTo: permissionDeniedView.centerYAnchor),
            permissionStack.leadingAnchor.constraint(greaterThanOrEqualTo: permissionDeniedView.leadingAnchor, constant: 24),
            permissionStack.trailingAnchor.constraint(lessThanOrEqualTo: permissionDeniedView.trailingAnchor, constant: -24),

            liveSignalCard.topAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: 6),
            liveSignalCard.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 14),
            liveSignalCard.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -14),

            liveSignalStack.topAnchor.constraint(equalTo: liveSignalCard.topAnchor, constant: 14),
            liveSignalStack.leadingAnchor.constraint(equalTo: liveSignalCard.leadingAnchor, constant: 14),
            liveSignalStack.trailingAnchor.constraint(equalTo: liveSignalCard.trailingAnchor, constant: -14),
            liveSignalStack.bottomAnchor.constraint(equalTo: liveSignalCard.bottomAnchor, constant: -14),

            waveformView.heightAnchor.constraint(equalToConstant: 140),

            vitalsCard.topAnchor.constraint(equalTo: liveSignalCard.bottomAnchor, constant: 12),
            vitalsCard.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 14),
            vitalsCard.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -14),
            vitalsCard.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -14),

            vitalsRow.topAnchor.constraint(equalTo: vitalsCard.topAnchor, constant: 18),
            vitalsRow.leadingAnchor.constraint(equalTo: vitalsCard.leadingAnchor, constant: 14),
            vitalsRow.trailingAnchor.constraint(equalTo: vitalsCard.trailingAnchor, constant: -14),
            vitalsRow.bottomAnchor.constraint(equalTo: vitalsCard.bottomAnchor, constant: -18),
        ])
    }

    private func makeVitalsColumn(iconName: String, iconTint: UIColor, caption: String, valueLabel: UILabel, placeholder: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: iconName))
        icon.tintColor = iconTint
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.heightAnchor.constraint(equalToConstant: 20).isActive = true
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true

        let captionLabel = UILabel()
        captionLabel.text = caption
        captionLabel.textColor = Palette.textTertiary
        captionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        captionLabel.textAlignment = .center

        valueLabel.text = placeholder
        valueLabel.textColor = Palette.textPrimary
        valueLabel.font = .boldSystemFont(ofSize: 30)
        valueLabel.textAlignment = .center
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.6

        let stack = UIStackView(arrangedSubviews: [icon, captionLabel, valueLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        return stack
    }
}

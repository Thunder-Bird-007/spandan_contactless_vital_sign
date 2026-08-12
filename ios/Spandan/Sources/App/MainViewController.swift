import AVFoundation
import UIKit

/// Single-screen glue: camera lifecycle, permission handling, and wiring the real
/// analysis pipeline into the UI -- the iOS analog of MainActivity.kt. HR is a
/// real, validated CHROM/POS+FFT port (see Signal/RealHeartRateEstimator.swift).
/// SpO2 is a real ratio-of-ratios + linear-calibration estimate (see
/// Signal/LiveSpo2Estimator.swift), added purely additively alongside HR -- both
/// estimators read the same `signalBuffer` snapshot independently, neither one's
/// class references or modifies the other's.
final class MainViewController: UIViewController {

    private let previewContainer = UIView()
    private let overlayView = OverlayView()
    private let chartView = SignalChartView()
    private let hrLabel = UILabel()
    private let spo2Label = UILabel()
    private let permissionDeniedView = UIView()
    private let permissionRationaleLabel = UILabel()
    private let grantPermissionButton = UIButton(type: .system)

    private let cameraController = CameraController()
    private let signalBuffer = SignalBuffer(windowSeconds: SignalBuffer.windowDurationSeconds)
    private let heartRateEstimator = RealHeartRateEstimator()
    private let spo2Estimator = LiveSpo2Estimator()

    private var refreshTimer: Timer?

    // Tracks the permission state as of the last time we actually acted on it, so
    // viewWillAppear can tell "still the same state" apart from "changed while
    // backgrounded" -- see evaluatePermissionAndStart() below, same reasoning as
    // MainActivity's permissionGrantedLastKnown / onResume().
    private var permissionGrantedLastKnown = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
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

    /// Periodically refreshes the chart + HR/SpO2 text, decoupled from the camera
    /// analysis frame rate -- same 200ms cadence as MainActivity's
    /// startUiRefreshLoop().
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
        chartView.updateValues(samples.map { $0.green })

        // HR: real pipeline (detrend -> bandpass -> CHROM/POS -> FFT + switching
        // rule), see Signal/RealHeartRateEstimator.swift. nil until enough of the
        // buffer window has filled.
        if let hr = heartRateEstimator.update(samples: samples) {
            hrLabel.text = String(format: "HR: %.0f bpm", hr)
        } else {
            hrLabel.text = "HR: -- bpm"
        }

        // SpO2: real ratio-of-ratios + linear calibration, see
        // Signal/LiveSpo2Estimator.swift. Independent call on the same samples
        // snapshot -- does not read heartRateEstimator's state or vice versa.
        if let spo2 = spo2Estimator.update(samples: samples) {
            spo2Label.text = String(format: "SpO2: %.2f%%", spo2)
        } else {
            spo2Label.text = "SpO2: -- %"
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    // MARK: - Layout (programmatic, mirrors activity_main.xml's structure:
    // camera preview + overlays on top, live raw-signal chart, then HR/SpO2
    // readouts side by side)

    private func buildLayout() {
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.backgroundColor = .black

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(overlayView)

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

        chartView.translatesAutoresizingMaskIntoConstraints = false

        hrLabel.textColor = .white
        hrLabel.font = .systemFont(ofSize: 20)
        hrLabel.textAlignment = .center
        hrLabel.text = "HR: -- bpm"

        spo2Label.textColor = .white
        spo2Label.font = .systemFont(ofSize: 20)
        spo2Label.textAlignment = .center
        spo2Label.text = "SpO2: -- %"

        let readoutStack = UIStackView(arrangedSubviews: [hrLabel, spo2Label])
        readoutStack.axis = .horizontal
        readoutStack.distribution = .fillEqually
        readoutStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(previewContainer)
        view.addSubview(chartView)
        view.addSubview(readoutStack)

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

            // chartView's fixed height + the readout row's fixed content, plus this
            // == pin at the bottom, close the vertical layout system so
            // previewContainer's height is fully determined without needing an
            // explicit height constraint of its own -- the Auto Layout analog of
            // Android's layout_weight="1" fill-remaining-space behavior.
            chartView.topAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: 4),
            chartView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            chartView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            chartView.heightAnchor.constraint(equalToConstant: 120),

            readoutStack.topAnchor.constraint(equalTo: chartView.bottomAnchor, constant: 12),
            readoutStack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 12),
            readoutStack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -12),
            readoutStack.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -12),
        ])
    }
}

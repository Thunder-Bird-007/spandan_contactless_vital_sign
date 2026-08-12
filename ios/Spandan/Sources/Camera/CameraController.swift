import AVFoundation
import CoreVideo

/// Owns the AVCaptureSession lifecycle and the live video-frame analysis
/// pipeline -- the iOS analog of CameraX's ProcessCameraProvider setup in
/// MainActivity.bindUseCases() (android/app/.../MainActivity.kt), factored into
/// its own class since there's no CameraX-style "camera provider" abstraction on
/// iOS to lean on.
///
/// **Deliberate design choice, different from the Android port:** this pre-
/// rotates buffers to upright portrait via `AVCaptureConnection.videoOrientation
/// = .portrait` on the analysis output's own connection (left unmirrored --
/// `automaticallyAdjustsVideoMirroring = false`, `isVideoMirrored = false`),
/// rather than the Android port's approach of leaving the raw sensor buffer alone
/// and mapping all four rotation cases by hand in `CoordinateMapper.
/// rotatedRectToSensorRect`. That trades a per-frame rotate AVFoundation does
/// internally (negligible at 640x480/sub-30fps) for eliminating an entire
/// coordinate space -- and the exact class of bug the Android port needed two
/// real-device fixes to find (see android/README.md's "Verification: what I
/// actually tested" section): here there is no separate "sensor space" the face
/// box and ROI need mapping out of before pixel-averaging, only before drawing
/// the on-screen overlay (see CoordinateMapper.swift).
///
/// **Not verified on a physical device or the Simulator** (which has no real
/// camera) -- see ../README.md's verification-status section before trusting
/// this pre-rotation assumption, or FaceAnalyzer's `.up` Vision-orientation
/// choice, without checking against a real device first.
final class CameraController: NSObject {

    enum PermissionState {
        case notDetermined
        case denied
        case granted
    }

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.spandan.app.session")
    private let analysisQueue = DispatchQueue(label: "com.spandan.app.analysis")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let faceAnalyzer = FaceAnalyzer()

    /// Called on `analysisQueue` for every analyzed frame -- callers must hop to
    /// the main thread before touching any views, same discipline as
    /// MainActivity.handleAnalysisResult()'s `uiHandler.post`.
    var onResult: ((FaceAnalysisResult) -> Void)?

    lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect // matches PreviewView's app:scaleType="fitCenter"
        return layer
    }()

    func currentPermissionState() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    func requestPermission(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.inputs.isEmpty {
                self.configureSession()
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 640x480 -- matches the ~640x480 sensor buffer size the Android port
        // observed on its real test device, and keeps per-frame pixel-averaging
        // cheap. Front camera on every iPhone this app targets supports this preset.
        session.sessionPreset = .vga640x480

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            return
        }
        session.addInput(input)

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        // Drop queued frames while the analyzer is busy, deliver only the newest
        // -- matches ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST in the Android port.
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: analysisQueue)

        guard session.canAddOutput(videoOutput) else { return }
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            connection.automaticallyAdjustsVideoMirroring = false
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = false
            }
        }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let result = faceAnalyzer.analyze(pixelBuffer: pixelBuffer)
        onResult?(result)
    }
}

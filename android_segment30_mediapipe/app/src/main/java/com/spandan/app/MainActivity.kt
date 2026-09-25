package com.spandan.app

import android.Manifest
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.widget.Button
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.spandan.app.camera.CoordinateMapper
import com.spandan.app.camera.FaceAnalysisResult
import com.spandan.app.camera.FaceAnalyzer
import com.spandan.app.signal.DisplaySmoother
import com.spandan.app.signal.EstimatorStatus
import com.spandan.app.signal.LiveSpo2Estimator
import com.spandan.app.signal.MorphologyWaveformEstimator
import com.spandan.app.signal.RealHeartRateEstimator
import com.spandan.app.signal.SignalBuffer
import com.spandan.app.ui.OverlayView
import com.spandan.app.ui.SignalChartView
import com.spandan.app.ui.WaveformView
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Single-screen glue: camera lifecycle, permission handling, and wiring the
 * real analysis pipeline into the UI. HR is a real, validated CHROM/POS+FFT
 * port (see signal/RealHeartRateEstimator.kt). SpO2 is a real ratio-of-ratios
 * + linear-calibration estimate (see signal/LiveSpo2Estimator.kt), added
 * purely additively alongside HR -- both estimators read the same
 * [signalBuffer] snapshot independently, neither one's class references or
 * modifies the other's.
 */
class MainActivity : AppCompatActivity() {

    private lateinit var previewView: PreviewView
    private lateinit var overlayView: OverlayView
    private lateinit var chartView: SignalChartView
    private lateinit var hrText: TextView
    private lateinit var spo2Text: TextView
    private lateinit var permissionDeniedView: View
    private lateinit var noFaceBanner: View
    private lateinit var hrStatusDot: View
    private lateinit var hrStatusLabel: TextView
    private lateinit var spo2StatusDot: View
    private lateinit var spo2StatusLabel: TextView
    private lateinit var morphologyWaveformView: WaveformView
    private lateinit var morphologyStatusDot: View
    private lateinit var morphologyStatusLabel: TextView

    private val signalBuffer = SignalBuffer(windowSeconds = SignalBuffer.WINDOW_DURATION_SECONDS)
    private val heartRateEstimator = RealHeartRateEstimator()
    private val spo2Estimator = LiveSpo2Estimator()

    // Segment 19 -- Branch 2 (waveform morphology / dicrotic notch), reading
    // the SAME signalBuffer snapshot as the two estimators above, completely
    // independently (matches Branch 1/Branch 2's deliberate MATLAB-side
    // separation -- see MorphologyWaveformEstimator's own KDoc).
    private val morphologyEstimator = MorphologyWaveformEstimator()

    // Segment 16 Task 1 -- DISPLAY-LEVEL smoothing only (see DisplaySmoother's
    // own KDoc for why this is not a re-introduction of the RAKF/Kalman
    // approach MATLAB already rejected). ON by default as of 2026-09-14,
    // after a real on-device A/B capture showed a genuine reduction in
    // tick-to-tick jitter with no accuracy cost -- see
    // ENABLE_HR_DISPLAY_SMOOTHING_DEFAULT's own KDoc below and
    // docs/Segment16_Task1_HR_Stability.md for the full result/caveats.
    private val hrDisplaySmoother = DisplaySmoother(mode = DisplaySmoother.Mode.ROLLING_MEDIAN)
    private val enableHrDisplaySmoothing = ENABLE_HR_DISPLAY_SMOOTHING_DEFAULT

    private var cameraProvider: ProcessCameraProvider? = null
    private val analysisExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val uiHandler = Handler(Looper.getMainLooper())

    // Segment 16 Task 3 -- when a face was last seen, for the "No face
    // detected" banner's debounce (see handleAnalysisResult/refreshUi
    // below). A single missed frame is normal (FaceAnalyzer's own
    // every-Nth-frame detection-skip design, plus ordinary detector noise)
    // and must NOT flash the banner -- only a SUSTAINED gap should.
    private var lastFaceSeenMs: Long = 0L

    // Tracks the permission state as of the last time we actually acted on it
    // (onCreate or a resume), so onResume can tell "still the same state" apart
    // from "changed while backgrounded" -- see onResume() below.
    private var permissionGrantedLastKnown = false

    private val requestPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            permissionGrantedLastKnown = granted
            if (granted) startCamera() else showPermissionDenied()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        previewView = findViewById(R.id.previewView)
        overlayView = findViewById(R.id.overlayView)
        chartView = findViewById(R.id.chartView)
        hrText = findViewById(R.id.hrText)
        spo2Text = findViewById(R.id.spo2Text)
        permissionDeniedView = findViewById(R.id.permissionDeniedView)
        noFaceBanner = findViewById(R.id.noFaceBanner)
        hrStatusDot = findViewById(R.id.hrStatusDot)
        hrStatusLabel = findViewById(R.id.hrStatusLabel)
        spo2StatusDot = findViewById(R.id.spo2StatusDot)
        spo2StatusLabel = findViewById(R.id.spo2StatusLabel)
        morphologyWaveformView = findViewById(R.id.morphologyWaveformView)
        morphologyStatusDot = findViewById(R.id.morphologyStatusDot)
        morphologyStatusLabel = findViewById(R.id.morphologyStatusLabel)

        // App targets SDK 35, where edge-to-edge is enforced -- content draws
        // behind system bars by default. Without this, the bottom HR/SpO2
        // status chips get clipped by the device's nav bar (found via
        // on-device screenshot during an earlier task's verification, same
        // "check the real device, don't assume" discipline as the
        // CoordinateMapper bugs).
        val rootLayout = findViewById<View>(R.id.rootLayout)
        ViewCompat.setOnApplyWindowInsetsListener(rootLayout) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }

        findViewById<Button>(R.id.grantPermissionButton).setOnClickListener {
            requestPermissionLauncher.launch(Manifest.permission.CAMERA)
        }

        permissionGrantedLastKnown = hasCameraPermission()
        if (permissionGrantedLastKnown) {
            startCamera()
        } else {
            requestPermissionLauncher.launch(Manifest.permission.CAMERA)
        }

        startUiRefreshLoop()
    }

    /**
     * Re-checks camera permission every time the activity resumes, not just at
     * onCreate. Without this, a user who denies the permission, backgrounds the
     * app, grants it via system Settings, and returns would stay stuck on the
     * "permission denied" screen -- onCreate's one-time check never re-runs on
     * a plain resume (only on activity re-creation). Compares against
     * [permissionGrantedLastKnown] rather than unconditionally acting every
     * resume, so this is a no-op on the very first resume right after onCreate
     * (before the initial permission dialog has even been answered) and on
     * every ordinary resume where nothing changed.
     */
    override fun onResume() {
        super.onResume()
        val granted = hasCameraPermission()
        if (granted == permissionGrantedLastKnown) return
        permissionGrantedLastKnown = granted

        if (granted) {
            // Denied earlier, granted since (e.g. via system Settings) while backgrounded.
            startCamera()
        } else {
            // Was granted, revoked since (e.g. via system Settings) while backgrounded.
            cameraProvider?.unbindAll()
            cameraProvider = null
            showPermissionDenied()
        }
    }

    private fun hasCameraPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED

    private fun showPermissionDenied() {
        // Graceful denial state -- no crash, just an explanation + a retry button.
        permissionDeniedView.visibility = View.VISIBLE
    }

    private fun startCamera() {
        permissionDeniedView.visibility = View.GONE

        val providerFuture = ProcessCameraProvider.getInstance(this)
        providerFuture.addListener({
            cameraProvider = providerFuture.get()
            bindUseCases()
        }, ContextCompat.getMainExecutor(this))
    }

    @OptIn(ExperimentalGetImage::class)
    private fun bindUseCases() {
        val provider = cameraProvider ?: return
        provider.unbindAll()

        val preview = Preview.Builder().build().also {
            it.setSurfaceProvider(previewView.surfaceProvider)
        }

        val analysis = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()

        val analyzer = FaceAnalyzer { result ->
            // Analyzer callback runs on analysisExecutor; hop back to the
            // main thread before touching any views.
            uiHandler.post { handleAnalysisResult(result) }
        }
        analysis.setAnalyzer(analysisExecutor, analyzer)

        try {
            provider.bindToLifecycle(
                this,
                CameraSelector.DEFAULT_FRONT_CAMERA,
                preview,
                analysis
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to bind CameraX use cases", e)
        }
    }

    private fun handleAnalysisResult(result: FaceAnalysisResult) {
        when (result) {
            is FaceAnalysisResult.NoFace -> overlayView.update(null, null)

            is FaceAnalysisResult.FaceDetected -> {
                lastFaceSeenMs = System.currentTimeMillis()

                val viewWidth = previewView.width
                val viewHeight = previewView.height

                val faceView = CoordinateMapper.rotatedRectToViewRect(
                    result.faceBoxRotated, result.rotatedImageWidth, result.rotatedImageHeight,
                    viewWidth, viewHeight, isFrontCamera = true
                )
                val roiView = CoordinateMapper.rotatedRectToViewRect(
                    result.roiBoxRotated, result.rotatedImageWidth, result.rotatedImageHeight,
                    viewWidth, viewHeight, isFrontCamera = true
                )
                overlayView.update(faceView, roiView)

                result.rgbSample?.let { signalBuffer.add(it) }
            }
        }
    }

    /** Periodically refreshes the chart + HR text, decoupled from the camera
     *  analysis frame rate. */
    private fun startUiRefreshLoop() {
        val refreshIntervalMs = 200L
        val runnable = object : Runnable {
            override fun run() {
                refreshUi()
                uiHandler.postDelayed(this, refreshIntervalMs)
            }
        }
        uiHandler.post(runnable)
    }

    private fun refreshUi() {
        val samples = signalBuffer.snapshot()
        chartView.updateValues(samples.map { it.green })

        // Segment 16 Task 3 -- "No face detected" banner, debounced so a
        // single missed detection (normal noise, or one of FaceAnalyzer's
        // own every-Nth-frame skipped-detection cycles) doesn't flash it.
        val msSinceFace = System.currentTimeMillis() - lastFaceSeenMs
        val noFaceSustained = lastFaceSeenMs == 0L || msSinceFace > NO_FACE_DEBOUNCE_MS
        noFaceBanner.visibility = if (noFaceSustained) View.VISIBLE else View.GONE

        // HR: real pipeline (detrend -> bandpass -> CHROM/POS -> FFT), see
        // signal/RealHeartRateEstimator.kt. Null until enough of the buffer window
        // has filled.
        val hrRaw = heartRateEstimator.update(samples)
        // Segment 16 Task 1 -- display-level smoothing only, gated off by
        // default (see the field's own KDoc above). When disabled this is a
        // pure passthrough (DisplaySmoother.Mode.NONE-equivalent), so hrBpm
        // is byte-for-byte hrRaw unless explicitly enabled.
        val hrBpm = if (enableHrDisplaySmoothing) hrDisplaySmoother.smooth(hrRaw) else hrRaw
        hrText.text = if (hrBpm != null) {
            getString(R.string.hr_format, hrBpm)
        } else {
            getString(R.string.hr_placeholder_default)
        }
        applyStatusPill(
            dot = hrStatusDot, label = hrStatusLabel, noFace = noFaceSustained,
            status = heartRateEstimator.lastStatus, okText = getString(R.string.status_ok_hr)
        )

        // SpO2: real ratio-of-ratios + linear calibration, see
        // signal/LiveSpo2Estimator.kt. Independent call on the same samples
        // snapshot -- does not read heartRateEstimator's state or vice versa.
        val spo2 = spo2Estimator.update(samples)
        spo2Text.text = if (spo2 != null) {
            getString(R.string.spo2_format, spo2)
        } else {
            getString(R.string.spo2_placeholder_default)
        }
        applyStatusPill(
            dot = spo2StatusDot, label = spo2StatusLabel, noFace = noFaceSustained,
            status = spo2Estimator.lastStatus, okText = getString(R.string.status_ok_spo2)
        )

        // Segment 19 -- Branch 2 morphology, independent call on the same
        // samples snapshot (does not read heartRateEstimator/spo2Estimator
        // state or vice versa, matching Branch 1/Branch 2's deliberate
        // MATLAB-side separation).
        val morphologyEstimate = morphologyEstimator.update(samples)
        morphologyWaveformView.update(
            morphologyEstimate?.waveform,
            morphologyEstimate?.notchDetected ?: false,
            morphologyEstimate?.notchPositionNormalized ?: Double.NaN
        )
        applyMorphologyStatusPill(noFaceSustained, morphologyEstimator.lastStatus, morphologyEstimate)
    }

    /**
     * Segment 19 -- like [applyStatusPill], but additionally surfaces the
     * notch CONFIDENCE VALUE in the label text (per this task's own
     * instruction: "surface the confidence score in the UI, not just a
     * yes/no" -- [NotchDetectIEM]'s own boolean `detected` output is a
     * near-useless gate at pool scale on the MATLAB side, so a bare
     * "detected"/"not detected" label here would repeat that same mistake).
     * When [status] is OK, the dot color additionally reflects whether the
     * RAW confidence clears this project's own 0.3 bar (green) or not
     * (amber) -- EstimatorStatus.OK alone only means "a value was computed
     * this tick," not "that value was a confident notch."
     */
    private fun applyMorphologyStatusPill(noFace: Boolean, status: EstimatorStatus, estimate: MorphologyWaveformEstimator.Estimate?) {
        val (color, text) = when {
            noFace -> R.color.status_no_face to getString(R.string.status_no_face)
            status == EstimatorStatus.WARMING_UP -> R.color.status_warming to getString(R.string.status_warming_up)
            status == EstimatorStatus.LOW_SIGNAL_QUALITY -> R.color.status_low_quality to getString(R.string.status_low_signal)
            estimate == null -> R.color.status_warming to getString(R.string.status_warming_up)
            !estimate.notchDetected -> R.color.status_low_quality to getString(R.string.morphology_no_notch)
            else -> {
                val methodLabel = if (estimate.harmonicMethodUsed == "gaussian015") {
                    getString(R.string.morphology_method_gaussian)
                } else {
                    getString(R.string.morphology_method_abpf)
                }
                val statusColor = if (estimate.notchConfidenceRaw > MORPHOLOGY_CONFIDENCE_BAR) R.color.status_ok else R.color.status_low_quality
                statusColor to getString(R.string.morphology_status_format, methodLabel, estimate.notchConfidenceRaw)
            }
        }
        val tint = ColorStateList.valueOf(ContextCompat.getColor(this, color))
        morphologyStatusDot.backgroundTintList = tint
        morphologyStatusLabel.text = text
        morphologyStatusLabel.setTextColor(ContextCompat.getColor(this, color))
    }

    /**
     * Segment 16 Task 1/2/3 -- maps an [EstimatorStatus] (plus the UI-only
     * "no face" case, which isn't one of the estimators' own states) onto a
     * status-pill color + label. Presentation-only: this function is never
     * called from, and never influences, either estimator's own computation.
     */
    private fun applyStatusPill(dot: View, label: TextView, noFace: Boolean, status: EstimatorStatus, okText: String) {
        val (color, text) = when {
            noFace -> R.color.status_no_face to getString(R.string.status_no_face)
            status == EstimatorStatus.WARMING_UP -> R.color.status_warming to getString(R.string.status_warming_up)
            status == EstimatorStatus.LOW_SIGNAL_QUALITY -> R.color.status_low_quality to getString(R.string.status_low_signal)
            else -> R.color.status_ok to okText
        }
        val tint = ColorStateList.valueOf(ContextCompat.getColor(this, color))
        dot.backgroundTintList = tint
        label.text = text
        label.setTextColor(ContextCompat.getColor(this, color))
    }

    override fun onDestroy() {
        super.onDestroy()
        analysisExecutor.shutdown()
        uiHandler.removeCallbacksAndMessages(null)
    }

    companion object {
        private const val TAG = "SpandanMainActivity"

        /** Segment 16 Task 3 -- how long since a face was last detected
         *  before the "No face detected" banner appears. 1200ms is a few
         *  multiples of FaceAnalyzer's own DETECT_EVERY_N_FRAMES=3 skip
         *  cycle at this project's measured ~13-21fps range (a few hundred
         *  ms per cycle), so an ordinary skip cycle or one failed detection
         *  never flashes the banner, but a real sustained absence (phone
         *  set down, face turned away) shows it within about a second. Not
         *  tuned against a real on-device capture this session -- flagged
         *  for the on-device test alongside Task 1's smoothing evaluation. */
        private const val NO_FACE_DEBOUNCE_MS = 1200L

        /** Segment 16 Task 1 -- PROMOTED TO ON 2026-09-14 after a real
         *  on-device A/B capture (Galaxy A35, 83 distinct recomputes over
         *  ~66s): rolling-median smoothing cut mean tick-to-tick jump from
         *  17.46bpm to 5.49bpm (~69% reduction) and stdev from 24.63 to
         *  20.54bpm, with no accuracy cost (the raw switched value is still
         *  computed and logged unchanged; smoothing is display-only). Real
         *  bug found and fixed during that same test -- see
         *  DisplaySmoother.kt's own header -- before this result was
         *  trustworthy. Single session, single subject, no manual-pulse
         *  cross-check this round -- see docs/Segment16_Task1_HR_
         *  Stability.md for the full caveats and the remaining test ideas. */
        private const val ENABLE_HR_DISPLAY_SMOOTHING_DEFAULT = true

        /** Segment 19 -- this project's own standing notch-confidence bar
         *  (matches `morphology/harmonicFilterConfidenceGate.m`'s own
         *  `confidenceThreshold` default and every MATLAB-side notch
         *  pass/fail table), used here only to color the status pill --
         *  the numeric confidence itself is always shown regardless of
         *  which side of this bar it falls on. */
        private const val MORPHOLOGY_CONFIDENCE_BAR = 0.3
    }
}

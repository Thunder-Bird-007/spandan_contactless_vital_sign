package com.spandan.app

import android.Manifest
import android.content.pm.PackageManager
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
import com.spandan.app.signal.PlaceholderVitalsEstimator
import com.spandan.app.signal.RealHeartRateEstimator
import com.spandan.app.signal.SignalBuffer
import com.spandan.app.ui.OverlayView
import com.spandan.app.ui.SignalChartView
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Single-screen glue: camera lifecycle, permission handling, and wiring the
 * (real) analysis pipeline into the (real) UI, calling out to the (fake)
 * PlaceholderVitalsEstimator only for the two numbers that aren't real yet.
 */
class MainActivity : AppCompatActivity() {

    private lateinit var previewView: PreviewView
    private lateinit var overlayView: OverlayView
    private lateinit var chartView: SignalChartView
    private lateinit var hrText: TextView
    private lateinit var spo2Text: TextView
    private lateinit var permissionDeniedView: View

    private val signalBuffer = SignalBuffer(windowSeconds = SignalBuffer.WINDOW_DURATION_SECONDS)
    private val heartRateEstimator = RealHeartRateEstimator()
    private var cameraProvider: ProcessCameraProvider? = null
    private val analysisExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val uiHandler = Handler(Looper.getMainLooper())
    private val startTimeMs = System.currentTimeMillis()

    private val requestPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
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

        // App targets SDK 35, where edge-to-edge is enforced -- content draws
        // behind system bars by default. Without this, the bottom HR/SpO2 status
        // chips get clipped by the device's nav bar (found via on-device
        // screenshot during this task's verification, same "check the real
        // device, don't assume" discipline as the earlier CoordinateMapper bugs).
        val rootLayout = findViewById<View>(R.id.rootLayout)
        ViewCompat.setOnApplyWindowInsetsListener(rootLayout) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }

        findViewById<Button>(R.id.grantPermissionButton).setOnClickListener {
            requestPermissionLauncher.launch(Manifest.permission.CAMERA)
        }

        if (hasCameraPermission()) {
            startCamera()
        } else {
            requestPermissionLauncher.launch(Manifest.permission.CAMERA)
        }

        startUiRefreshLoop()
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

    /** Periodically refreshes the chart + placeholder HR/SpO2 text, decoupled
     *  from the camera analysis frame rate. */
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

        val elapsedSeconds = (System.currentTimeMillis() - startTimeMs) / 1000.0

        // HR: real pipeline (detrend -> bandpass -> CHROM/POS -> FFT), see
        // signal/RealHeartRateEstimator.kt. Null until enough of the buffer window
        // has filled.
        val hrBpm = heartRateEstimator.update(samples)
        hrText.text = if (hrBpm != null) {
            getString(R.string.hr_format, hrBpm)
        } else {
            getString(R.string.hr_placeholder_default)
        }

        // SpO2: still PLACEHOLDER math, untouched -- see
        // signal/PlaceholderVitalsEstimator.kt.
        val spo2 = PlaceholderVitalsEstimator.computeSpo2Placeholder(elapsedSeconds)
        spo2Text.text = getString(R.string.spo2_format, spo2)
    }

    override fun onDestroy() {
        super.onDestroy()
        analysisExecutor.shutdown()
        uiHandler.removeCallbacksAndMessages(null)
    }

    companion object {
        private const val TAG = "SpandanMainActivity"
    }
}

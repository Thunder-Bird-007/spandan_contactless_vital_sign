plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.spandan.app"
    compileSdk = 35

    defaultConfig {
        // [Segment 30] Suffixed so this MediaPipe-migration duplicate can be
        // installed alongside the production com.spandan.app build on the
        // same device, for direct A/B comparison -- see
        // android_segment30_mediapipe/docs/Segment30_MediaPipe_Migration.md.
        applicationId = "com.spandan.app.mediapipe"
        // CameraX and ML Kit Face Detection both support minSdk 21; 24 is used
        // here as a reasonable modern baseline for a course project, not a
        // hard library requirement.
        minSdk = 24
        targetSdk = 35
        versionCode = 2
        versionName = "1.1.0-branch2"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    // Segment 19 -- MorphologyWaveformEstimator (and RealHeartRateEstimator/
    // LiveSpo2Estimator before it, just never previously exercised by a
    // plain-JUnit test) call android.util.Log.d/.w directly. Log's real
    // implementation throws "not mocked" under plain JUnit (unlike
    // android.graphics.Rect, whose methods are plain Java with no native
    // call, and so already worked fine in CoordinateMapperTest/
    // OpticalFlowMatcherTest without this). This makes every unmocked
    // android.* call return a harmless default (Log.d/.w return 0) instead
    // of throwing, rather than wrapping every estimator's logging behind a
    // new testable indirection layer for no other purpose.
    testOptions {
        unitTests {
            isReturnDefaultValues = true
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")

    // --- CameraX: preview + on-device frame analysis ---
    val cameraxVersion = "1.3.4"
    implementation("androidx.camera:camera-core:$cameraxVersion")
    implementation("androidx.camera:camera-camera2:$cameraxVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraxVersion")
    implementation("androidx.camera:camera-view:$cameraxVersion")

    // --- ML Kit Face Detection (bundled model: works fully offline, no
    // Play Services download step needed, which is one less moving part for
    // a lab demo) ---
    implementation("com.google.mlkit:face-detection:16.1.7")

    // --- [Segment 30] MediaPipe Tasks Vision Face Detector (BlazeFace
    // short-range) -- a candidate replacement for ML Kit above, gated off by
    // default (see FaceAnalyzer.kt's useMediaPipeDetection flag). Kept
    // alongside ML Kit, not replacing it, until measured on-device -- this
    // project's own "evidence before promotion" convention. ---
    implementation("com.google.mediapipe:tasks-vision:1.0.0")

    // --- JTransforms: real FFT for signal/HeartRateFft.kt (matlab/src/heartrate/
    // fftHeartRate.m ported) --- added now that a real FFT step actually exists;
    // previously deferred (see android/README.md history) while HR was a placeholder.
    implementation("com.github.wendykierp:JTransforms:3.1")

    // NOTE (deliberate, not an oversight): the OpenCV Android SDK is NOT added.
    //  - ROI pixel averaging is done directly on the CameraX YUV_420_888
    //    planes (see camera/RoiPixelAverager.kt) without needing OpenCV's
    //    Mat/Bitmap machinery. If a later stage needs real image-processing
    //    ops (e.g. matching a MATLAB `imresize`/filtering step exactly),
    //    add OpenCV Android SDK then.
    // Flagged for the team to confirm against Spandan_Orientation_Lecture.pdf
    // if/when that document turns up -- see android/README.md.

    testImplementation("junit:junit:4.13.2")
}

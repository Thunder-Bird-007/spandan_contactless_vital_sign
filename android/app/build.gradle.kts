plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.spandan.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.spandan.app"
        // CameraX and ML Kit Face Detection both support minSdk 21; 24 is used
        // here as a reasonable modern baseline for a course project, not a
        // hard library requirement.
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0-skeleton"
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

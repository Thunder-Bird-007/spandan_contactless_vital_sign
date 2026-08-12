# Spandan iOS — app port

This is the iOS half of the Spandan project (see the [repo-root
README](../README.md) for the overall project, and [`../android/README.md`](../android/README.md)
for the Android app this is a port of).

## Status, stated plainly up front

**This port was written without access to a Mac, an iPhone, or Xcode.** Every
algorithmic file (`Spandan/Sources/Signal/`) is a line-for-line translation of
the Android app's own Kotlin source, which is itself a direct port of the
validated MATLAB pipeline -- read from the actual `android/app/.../signal/*.kt`
files before writing the Swift, not from memory or description. Those files,
plus the pure-math unit tests in `SpandanTests/`, are **verified by CI**
(`.github/workflows/ios-build.yml`, a macOS GitHub Actions runner) to actually
compile and produce correct numbers on synthetic test signals.

**The camera/Vision/UI layer (`Spandan/Sources/Camera/`, `Spandan/Sources/App/`,
`Spandan/Sources/UI/`) is NOT verified beyond "it compiles."** CI has no real
camera (the iOS Simulator doesn't have one), so nothing has confirmed that:

- the front camera actually opens and streams frames,
- Vision's face detection actually fires on live frames,
- the face box / ROI box overlay actually lines up with a real face on screen,
- the app doesn't crash on a real device.

The Android app's own README documents **two real coordinate-mapping bugs**
that were only found by running on a physical Samsung Galaxy A35 and reading
`adb logcat` output -- this port has had no equivalent chance yet. Read
[Known risk areas](#known-risk-areas-for-whoever-tests-this-on-a-real-iphone)
before demoing this, and treat every on-screen number as unverified until
someone with a physical iPhone has gone through that same discipline.

## What's ported, and how faithfully

| File | Ported from | Status |
|---|---|---|
| `Signal/RgbSample.swift` | `signal/RgbSample.kt` | Direct struct port |
| `Signal/SignalBuffer.swift` | `signal/SignalBuffer.kt` | Direct port, same 25s window |
| `Signal/BandpassFilter.swift` | `signal/BandpassFilter.kt` | Direct port: cubic detrend, Butterworth order-2 bandpass (bilinear transform), filtfilt with odd-reflection padding. Unit-tested (`BandpassFilterTests`, same synthetic-sine test as the Android port) -- **passes on CI** |
| `Signal/PulseExtraction.swift` | `signal/PulseExtraction.kt` | Direct port: exact CHROM/POS formulas, same raw-channel normalization judgment call |
| `Signal/HeartRateFft.swift` | `signal/HeartRateFft.kt` | **Same DFT math, different algorithm**: a direct O(band-width x n) DFT sum restricted to in-band bins, instead of JTransforms' O(n log n) full FFT + band mask. Numerically equivalent (see the file's own header note for why); unit-tested against a synthetic sine (`HeartRateFftTests`) |
| `Signal/RealHeartRateEstimator.swift` | `signal/RealHeartRateEstimator.kt` | Direct port, including the exact CHROM/POS switching rule (`docs/Android_HR_Switching_Port_Spec.md`, 29.27% threshold) -- the switching decision is factored into a pure, directly-testable function (`switchingDecision`), unit-tested at and around the threshold boundary |
| `Signal/LiveSpo2Estimator.swift` | `signal/LiveSpo2Estimator.kt` | Direct port: same ratio-of-ratios formula, same production calibration constants (`A=96.47630625`, `B=-0.4159452784`), same `A - B*R` sign convention (unit-tested explicitly, since this is exactly the sign bug the Android port's own KDoc had to flag), same 90-100% clamp |
| `Camera/RoiCalculator.swift` | `camera/RoiCalculator.kt` | Direct port, same fractions (`0.30/0.70/0.10/0.30`) reconciled against MATLAB |
| `Camera/RoiPixelAverager.swift` | `camera/RoiPixelAverager.kt` | Same BT.601 full-range YUV->RGB formula, adapted to iOS's bi-planar (NV12-style) pixel format instead of Android's generic 3-plane `YUV_420_888` |
| `Camera/FaceAnalyzer.swift` | `camera/FaceAnalyzer.kt` | Same orchestration shape (detect -> largest face -> ROI -> pixel-average), Vision (`VNDetectFaceRectanglesRequest`) instead of ML Kit -- **unverified orientation assumption, see below** |
| `Camera/CoordinateMapper.swift` | `camera/CoordinateMapper.kt` | Only ports `rotatedRectToViewRect` (the overlay-placement math) -- the sensor-space mapping function isn't needed here, see `CameraController.swift`'s header comment for why |
| `Camera/CameraController.swift` | `MainActivity.kt`'s camera lifecycle glue | New structure (no CameraX equivalent on iOS), but the same responsibilities: session lifecycle, permission state, frame delivery |
| `App/MainViewController.swift` | `MainActivity.kt` | Same single-screen structure and behavior: permission handling with a re-check on every appearance, 200ms UI refresh loop, independent HR/SpO2 estimator calls |
| `UI/OverlayView.swift`, `UI/SignalChartView.swift` | `ui/OverlayView.kt`, `ui/SignalChartView.kt` | Direct visual port: same colors, same plain-Core-Graphics-draw approach (no chart library) |

## Known risk areas for whoever tests this on a real iPhone

**In order of how likely they are to be wrong**, since nothing camera-related
has been run on real hardware:

1. **`CameraController`'s pre-rotation assumption.** This port sets
   `AVCaptureConnection.videoOrientation = .portrait` on the analysis output's
   connection, on the assumption that AVFoundation will then deliver
   `CVPixelBuffer`s already rotated to upright portrait dimensions (eliminating
   the sensor-vs-rotated coordinate-space split the Android port had to handle
   by hand). This is a well-documented, commonly-used AVFoundation pattern, but
   it has not been confirmed against this app's actual buffers. If it's wrong,
   `FaceAnalyzer`'s `orientation: .up` Vision request and every downstream
   box will be off.
2. **Front-camera mirroring.** `automaticallyAdjustsVideoMirroring = false` +
   `isVideoMirrored = false` on the analysis connection is meant to give
   Vision/`RoiPixelAverager` a raw, unmirrored buffer, while the *preview*
   layer's own (separate, default) connection still mirrors for the user --
   `CoordinateMapper.viewRect(..., isFrontCamera: true)` then re-applies the
   mirror when placing the overlay. If preview mirroring and analysis
   mirroring don't actually behave the way that reasoning assumes on real
   hardware, the overlay will be flipped relative to the face.
3. **`.vga640x480` session preset support.** Assumed supported by every
   front camera this targets (true for all iPhones with iOS 16+, as far as
   Apple's documented preset-support tables go), but not directly confirmed.
4. **Everything downstream of 1-2**: ROI placement, pixel averaging region,
   and on-screen overlay alignment all depend on those two assumptions being
   right. Debug the same way the Android README's "Verification" section
   did -- log the raw buffer dimensions, the Vision `boundingBox`, and the
   final view-space rect at each stage, and check them against a real
   screenshot, rather than assuming the math above is correct just because it
   compiles.
5. **HR/SpO2 on-screen accuracy**, once the above is confirmed correct. The
   Android port's own README is explicit that even *its* verified,
   correctly-aligned pipeline shows real reading-to-reading jitter against a
   manual pulse count (see its "Verification: the HR port" section) -- there
   is no reason to expect this port's numbers to be any more stable without
   its own equivalent multi-minute on-device runs.

## How to build (needs a Mac)

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
   if you don't have it.
2. From this `ios/` directory: `xcodegen generate`. This produces
   `Spandan.xcodeproj` (gitignored, regenerate rather than hand-edit -- see
   `project.yml` for the actual project spec).
3. Open `Spandan.xcodeproj` in Xcode.
4. Under the `Spandan` target's **Signing & Capabilities**, set your own
   development team (the committed `project.yml` deliberately has none baked
   in, since that's personal to whoever's Apple ID is building it).
5. Run on a **physical iPhone with a front camera** -- the Simulator has no
   real camera, so the face-detection/RGB pipeline cannot be exercised there
   at all (only compilation and the pure-math unit tests can). Minimum iOS
   16.0.
6. Grant the camera permission when prompted.

## CI: what's actually been verified, and how

There's no Mac available to whoever wrote this port, so `.github/workflows/
ios-build.yml` is the only thing that has actually compiled this code and run
its tests, on a `macos-14` GitHub Actions runner:

1. Installs XcodeGen, runs `xcodegen generate`.
2. `xcodebuild build` for an iOS Simulator destination (no code signing
   needed for Simulator builds) -- confirms the whole app target, camera code
   included, actually compiles.
3. `xcodebuild test` on the same destination -- runs every test in
   `SpandanTests/`: `BandpassFilterTests` (ported from the Android unit test),
   `HeartRateFftTests`, `RealHeartRateEstimatorSwitchingTests`,
   `LiveSpo2EstimatorTests`, `PulseExtractionTests`.

This proves the algorithmic core is correct on synthetic signals and that
nothing fails to compile -- it does **not** prove the camera pipeline works on
a real device, for the reasons in
[Known risk areas](#known-risk-areas-for-whoever-tests-this-on-a-real-iphone)
above. Check the Actions tab (or `gh run list`/`gh run view`) for the current
status of this workflow before trusting either claim.

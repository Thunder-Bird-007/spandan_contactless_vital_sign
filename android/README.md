# Spandan Android — app skeleton

This is the Android half of the Spandan project (see the [repo-root
README](../README.md) for the overall project: HR/SpO2 from facial video via
classical DSP, currently being developed in MATLAB under `../matlab/`).

## Download & Install

Don't want to build it yourself? Grab the latest debug APK from the
[Releases page](https://github.com/Thunder-Bird-007/spandan_contactless_vital_sign/releases/latest)
(always points to the newest build).

1. On an **Android 7.0+** phone (minSdk 24), open the release page above and
   download `app-debug.apk`.
2. If prompted, allow **"install from unknown sources"** for your browser/
   file manager (Android will ask automatically the first time).
3. Open the downloaded APK and install it.
4. Launch the app and grant the **camera permission** when asked -- it's
   required for the HR/SpO2 pipeline to run.

This is a debug build for demo/sideload purposes, not a Play Store release --
see [What's real vs. placeholder](#whats-real-vs-placeholder) below before
treating an on-screen reading as a validated medical measurement.

**This build ships both a real HR pipeline and a real, live SpO2 estimate.**
The camera → face detection → ROI → signal pipeline is fully wired end to
end. HR is a real port of the validated MATLAB CHROM/POS+FFT pipeline (see
[What's real vs. placeholder](#whats-real-vs-placeholder) and
[Verification: the HR port](#verification-the-hr-port-segment-4) below) --
but its on-device accuracy has **not** been shown to match MATLAB's
validated full-pool result (CHROM MAE ~9.10bpm, r=0.31; POS MAE ~8.68bpm,
r=0.28 -- N=112, 5 UBFC + 107 VIPL), for reasons explained in that
section. SpO2 went
through three states across this project's history, in order: (1) fake
placeholder math, (2) removed outright (no validated calibration existed to
ship), (3) **the current state -- a real, live ratio-of-ratios + linear
calibration estimate** (`signal/LiveSpo2Estimator.kt`), added once Task R
confirmed the production calibration formula transfers to phone-camera data
without needing device-specific centering. See
[`docs/SpO2_Live_Implementation.md`](docs/SpO2_Live_Implementation.md) for
the exact formula, on-device verification, and the confidence caveat its
UI subtitle states plainly. Read the verification sections below before
anyone mistakes a build screenshot for a fully validated result.

**Defense-readiness status, standing decision, and the current stability-run
result live in
[`docs/Defense_Readiness_Checklist.md`](docs/Defense_Readiness_Checklist.md)
-- read that first for "is this ready to demo," this file is the detailed
build log/history behind it.**

## Why this exists / how it fits the timeline

`../matlab/` originally hadn't finished formal LOSO validation (Segment 6),
so there were no finalized bandpass filter coefficients, CHROM/POS formulas,
or SpO2 calibration constants to port. This skeleton was built
**algorithm-independent** first — camera capture, live preview, on-device
face detection, ROI cropping, RGB spatial averaging, buffering, and UI —
with obvious placeholder math standing in for the parts that depended on
MATLAB's final numbers.

**Update:** MATLAB's HR pipeline (CHROM/POS-based FFT heart rate) has since
been validated -- CHROM MAE ~9.10bpm, r=0.31; POS MAE ~8.68bpm, r=0.28,
pooled across the full N=112 (5 UBFC + 107 VIPL) -- and has now been
ported for real; see
[Verification: the HR port](#verification-the-hr-port-segment-4) below.
SpO2 calibration is explicitly **still unresolved** on the MATLAB side (the
pooled calibration doesn't beat a trivial "guess the mean" baseline yet) --
see `../matlab/docs/SpO2_Final_Report_Section.md`, whose own standing
decision is "not approved for Android display." **Superseded:** the
paragraph below originally said `PlaceholderVitalsEstimator.kt`'s
`computeSpo2Placeholder()` would stay untouched until a real calibration
landed. That plan changed for defense readiness: rather than ship a fake
number a demo audience could mistake for real, SpO2 was removed from the
app outright -- `PlaceholderVitalsEstimator.kt` is deleted, and there is no
SpO2 view/string anywhere in the UI. It will be added back for real, not
restored as a placeholder, once MATLAB has a validated calibration to port.

**MATLAB-side Tasks L/N/O/P were investigated but deliberately not
ported.** Segment 6 explored on-device evaluation (L), multi-region ROI
(N), detrend/adaptive-bandpass refinement (O), and windowed harmonic
continuity (P) as possible accuracy improvements. None of that logic is in
this Android build -- the app ships the original validated pipeline
(single forehead ROI, whole-clip FFT, no windowing/continuity/multi-region
logic) as a deliberate, evidence-based call: porting late-stage MATLAB
experiments this close to defense was judged higher regression risk than
the runway available to re-verify them on-device.

## What's real vs. placeholder

**Real, permanent** (this logic is correct and stays as-is going forward):

| File | What it does |
|---|---|
| `MainActivity.kt` | Camera lifecycle, permission handling, UI wiring, window-inset padding |
| `camera/FaceAnalyzer.kt` | Runs ML Kit face detection per frame via CameraX `ImageAnalysis` (no naive per-frame Bitmap conversion for detection) |
| `camera/RoiCalculator.kt` | Derives the forehead ROI as a fractional sub-crop of the face box — fractions now reconciled against MATLAB's validated geometry, see below |
| `camera/CoordinateMapper.kt` | Geometry: sensor-buffer ↔ ML-Kit-rotated ↔ on-screen-view coordinate conversions |
| `camera/RoiPixelAverager.kt` | Spatially averages R/G/B pixel intensities inside the ROI, sampled directly from the YUV planes |
| `signal/SignalBuffer.kt`, `signal/RgbSample.kt` | Rolling time-windowed buffer of RGB samples |
| `ui/OverlayView.kt`, `ui/SignalChartView.kt` | Face/ROI box overlay, live raw-signal line chart |
| `signal/BandpassFilter.kt` | Real port of `filtering/detrendSignal.m` + `filtering/bandpassClean.m`: cubic detrend, Butterworth bandpass (bilinear-transform design) + filtfilt. Unit-tested, see verification below. |
| `signal/PulseExtraction.kt` | Real port of `pulseextraction/chromCombine.m` + `posCombine.m` (CHROM/POS) |
| `signal/HeartRateFft.kt` | Real port of `heartrate/fftHeartRate.m` (FFT peak-picking in the 0.7-4Hz band), via JTransforms |
| `signal/RealHeartRateEstimator.kt` | Wires the above into one pipeline against `SignalBuffer`'s window; displayed bpm is chosen per-reading by the CHROM/POS switching rule (see [switching estimator port](#chrompos-switching-estimator-port-segment-4-follow-up-4) below), CHROM/POS raw values still logged alongside for comparison |
| `signal/LiveSpo2Estimator.kt` | Real port of `spo2/ratioOfRatios.m` + the uncentered production linear calibration (`spo2/calibrateSpO2.m` coefficients, `matlab/docs/SpO2_Final_Calibration_Spec.md`). Independent of `RealHeartRateEstimator` -- see [`docs/SpO2_Live_Implementation.md`](docs/SpO2_Live_Implementation.md) for the exact formula, the sign-convention correction made while porting it, and on-device verification |

**Placeholder/removed (historical):**

| File | Status |
|---|---|
| ~~`signal/PlaceholderVitalsEstimator.kt`~~ | **Superseded -- deleted.** Used to hold `computeSpo2Placeholder()` (a fake sine oscillation) and an already-unused `computeHeartRatePlaceholder()`. Both are gone: HR has come from `RealHeartRateEstimator` since the HR port, and SpO2 has come from `LiveSpo2Estimator` since Task R (see below) -- neither placeholder function has a live caller anywhere in this app. |

**Superseded twice over -- SpO2 is live again.** This paragraph originally
described a fake "● PLACEHOLDER — not real" SpO2 chip; a later pass removed
SpO2's UI entirely (judged safer than a labeled-but-still-numeric fake
reading a demo audience could mistake for real). **That removal is itself
now superseded**: once Task R confirmed the production ratio-of-ratios
calibration transfers to phone-camera data without needing a device-specific
centering offset (`matlab/docs/Segment6_Task_R_Phone_SpO2_Centering.md`),
SpO2 was re-added as a real, live estimate -- `activity_main.xml` has a
`spo2Text` value + amber subtitle column again, matching HR's visual style.
See [`docs/SpO2_Live_Implementation.md`](docs/SpO2_Live_Implementation.md)
for the full formula/verification. HR still has a real DSP pipeline behind
it (see the "● LIVE" chip), but read
[Verification: the HR port](#verification-the-hr-port-segment-4) before
trusting its on-device *accuracy* -- the pipeline is a faithful port, but
this build's buffer window (**25s**, raised from the original 10s -- see
[Window-length change: 10s → 25s](#window-length-change-10s--25s-segment-4-follow-up-2)
below) means its instantaneous readings are still noisier than MATLAB's
validated offline result.

### The ROI fraction placeholder (superseded -- reconciled against MATLAB)

`RoiCalculator.foreheadRoiFrom()` crops a forehead band using four hardcoded
fractions of the face box. This section used to say those fractions (top
8–30%, horizontally centered 25–75%) were chosen by eye and **not
reconciled** against MATLAB. That reconciliation has now been done directly
against `matlab/src/roi/extractROISignals.m`'s `computeRegionBBoxes`
(default/original `forehead` mode): MATLAB uses `xFracLo=0.30, xFracHi=0.70,
yFracLo=0.10, yFracHi=0.30` -- the exact geometry Segment 6's validated
full-pool HR result (CHROM MAE ~9.10bpm, r=0.31) was computed against.
The by-eye fractions genuinely did
not match (25–75%/8–30% vs. the real 30–70%/10–30%), so this was a real gap,
not stale documentation -- `RoiCalculator.kt`'s four constants are now
`TOP_FRACTION=0.10f, BOTTOM_FRACTION=0.30f, LEFT_FRACTION=0.30f,
RIGHT_FRACTION=0.70f`, matching MATLAB exactly.

### No orientation/bridge document found

The task that produced this skeleton asked me to check for a
`Spandan_Orientation_Lecture.pdf` (or similar) with a MATLAB→Android
technology-mapping table, to follow it instead of guessing. I searched the
whole repo and found no such document — only the four Segment 2–5 guideline
PDFs (`../segment*/Segment*_Guideline.pdf`), which are MATLAB-side DSP specs,
not Android technology guidance. **The technology choices below (ML Kit for
face detection, CameraX for capture) were made independently, not from a
lecture bridge document.** Flag this for the team to confirm if that PDF
turns up later — if it specifies different libraries or a different ROI
convention, this skeleton will need adjusting.

### Other technology decisions worth flagging

- **OpenCV Android SDK was not added.** ROI pixel averaging is done directly
  on CameraX's YUV_420_888 planes (`RoiPixelAverager.kt`) with a standard
  BT.601 YUV→RGB conversion — no image library needed for that. If a later
  stage needs to match a specific MATLAB image op exactly, add OpenCV then.
- **JTransforms was added** (`com.github.wendykierp:JTransforms:3.1`,
  `app/build.gradle.kts`) now that `signal/HeartRateFft.kt` has a real
  frequency-domain step to run (complex FFT, magnitude taken per positive
  bin, matching `fftHeartRate.m`).
- **Coordinate-mapping math has been verified on a real device and two real
  bugs were found and fixed** — see
  [Verification](#verification-what-i-actually-tested) below for the full
  story. Short version: (1) the preview's `PreviewView` was left at its
  default `FILL_CENTER` scale type while `CoordinateMapper` assumed
  `FIT_CENTER`, and (2) `FaceAnalyzer` trusted
  `InputImage.fromMediaImage(...).width/.height` to report rotation-swapped
  dimensions, but on-device they're the raw unrotated sensor dimensions —
  ML Kit's `Face.getBoundingBox()` is genuinely in rotated/upright space, so
  the mismatch threw off the view-mapping scale and offset. Both are fixed
  now (`app:scaleType="fitCenter"` on the `PreviewView`, and `FaceAnalyzer`
  deriving rotated width/height itself from the raw sensor dimensions +
  `rotationDegrees` instead of trusting `InputImage`'s getters). Also worth
  knowing: the real device used for testing reports `rotationDegrees = 270`
  for the front camera in portrait, not the `90` this file originally
  assumed as "the default" — both are handled identically by the fix (same
  swap-width/height branch), so this didn't need special-casing, but it's
  a reminder not to assume a single rotation value across devices.

## Project structure

```
android/
  app/
    build.gradle.kts        - dependencies (CameraX, ML Kit)
    src/main/
      AndroidManifest.xml
      java/com/spandan/app/
        MainActivity.kt
        camera/              - real: detection, ROI, coordinate mapping, pixel averaging
        signal/              - real: buffer/model classes + the HR and SpO2 pipelines (no placeholder files remain)
        ui/                  - real: overlay + chart custom Views
      res/                   - layout, strings, theme
  settings.gradle.kts / build.gradle.kts / gradle.properties
```

## How to run

1. Open the `android/` folder (this folder, not the repo root) directly in
   **Android Studio** (Jellyfish/Koala or newer recommended).
2. The Gradle wrapper (`gradlew`/`gradlew.bat`) is committed (see note
   below), so Android Studio should sync directly using it.
3. Let Gradle sync finish. It needs **Android SDK Platform 35** (bumped from
   the original 34 target — see `app/build.gradle.kts`) and a recent
   **build-tools** version installed via the SDK Manager if you don't have
   them already.
4. Run on a **physical device** with a front camera (recommended — face
   detection + realistic lighting matters here) or an emulator with a
   virtual front-camera feed. Minimum SDK is 24 (Android 7.0).
5. Grant the camera permission when prompted.

**`gradlew`/`gradlew.bat` are now committed** (generated via a locally
cached Gradle 8.7 install and `gradle wrapper`, then verified with a real
`assembleDebug`) — you don't need Android Studio to bootstrap them anymore,
though opening in Android Studio still works fine too.

**A pitfall hit running the wrapper from a plain terminal (not Android
Studio):** Gradle 8.7's daemon needs JDK 8-21; if your machine's default
`java`/`JAVA_HOME` is newer (e.g. JDK 25), the wrapper fails with a cryptic,
near-content-free error (just the JDK version number as the failure
message, no stack trace pointing at the real cause). Point `JAVA_HOME` at a
compatible JDK instead -- Android Studio ships one that works fine, usually
at `<Android Studio install dir>/jbr`. Also, `adb` isn't necessarily on
`PATH` outside Android Studio's Terminal -- it's at
`<sdk.dir from local.properties>/platform-tools/adb.exe`.

## Verification: what I actually tested

**VERIFIED on real hardware.** Built and ran on a physical **Samsung Galaxy
A35 (SM-A356E), Android 14/One UI 6.x**, over adb, using Android SDK
Platform 35 / build-tools installed locally and a Gradle 8.7 install
(wrapper generated and committed, see above). `./gradlew assembleDebug`
built clean on the first try — no compile errors — with one harmless
warning (`@OptIn(ExperimentalGetImage::class)` is flagged as a no-op by the
Kotlin compiler because that particular CameraX annotation isn't a real
`@RequiresOptIn` marker; doesn't affect behavior, left as-is).

### Bugs found and fixed during verification

Two real bugs surfaced in the untested `CoordinateMapper` geometry — both
now fixed, and both were about coordinate-space bookkeeping, not the math
inside `CoordinateMapper` itself (which was correct once fed the right
inputs):

1. **`PreviewView` scale-type mismatch.** `activity_main.xml` never set
   `app:scaleType` on the `PreviewView`, so it silently ran at its default
   `FILL_CENTER` (crops to fill, no letterbox) while
   `CoordinateMapper.rotatedRectToViewRect`'s scale/offset math explicitly
   assumed `FIT_CENTER` (uniform scale, letterboxed, never cropped). Fixed
   by adding `app:scaleType="fitCenter"` to the `PreviewView` in
   `activity_main.xml`. Confirmed by the preview gaining visible letterbox
   bars top/bottom after the fix.
2. **`InputImage` dimensions aren't rotation-swapped (the real cause of the
   visible offset).** `FaceAnalyzer` used
   `InputImage.fromMediaImage(mediaImage, rotationDegrees).width/.height`
   as the "rotated image" dimensions, trusting the old KDoc claim that
   these come back swapped for 90°/270° rotation. On-device logging showed
   otherwise: at `rotationDegrees = 270` (this device's actual front-camera
   portrait value — not the `90` originally assumed as default),
   `inputImage.width/height` reported `640x480`, identical to the raw,
   unrotated sensor buffer. But `Face.getBoundingBox()` genuinely *is*
   returned in the rotated/upright space (480×640). Feeding the wrong,
   unswapped `640x480` as `srcWidth/srcHeight` into the view-mapping scale
   math produced a face box that was visibly offset right and down from
   the actual face — small enough to still look plausible (not obviously
   broken) but wrong enough to cut off part of the face and include
   background. Fixed by having `FaceAnalyzer` derive the true rotated
   width/height itself from `imageProxy.width/height` +
   `rotationDegrees` (swap for 90/270, keep as-is for 0/180) instead of
   trusting `InputImage`'s getters. `CoordinateMapper.kt`'s KDoc has been
   corrected to document this instead of the wrong assumption.

Root-caused by adding temporary `Log.d` calls at each coordinate-space
boundary (raw sensor dims, `InputImage` dims, `rotationDegrees`,
`Face.getBoundingBox()`, the final view-space rect) and reading real
numbers off `adb logcat` rather than guessing further from the screenshots
alone; the diagnostic logging was removed again once the fix was
confirmed. `RoiPixelAverager`/`rotatedRectToSensorRect` (the actual pixel
averaging used for the RGB signal, as opposed to the on-screen overlay)
was **not** affected by either bug — it was already being called with raw
`imageProxy.width/height` directly, not `InputImage`'s, so the signal
extraction itself was unaffected throughout.

### What was checked, and the result

- **Camera preview**: renders full-screen, no crash. ✅
- **Permission-denied state**: confirmed via `adb`-driven testing (`pm
  revoke` + UI dumps/screenshots, since a device-side auto-answer behavior
  — see note below — made the dialog hard to catch by eye alone). Denying
  shows the rationale text + "Grant camera permission" button, banner and
  HR/SpO2 text keep updating underneath, no crash. Tapping the button
  re-invokes the permission request without crashing. Granting (either via
  the real dialog or externally, simulating Settings) and returning to the
  app starts the camera correctly — full recovery confirmed, no crash at
  any point in the cycle. ✅
  - **Superseded -- fixed.** This used to flag that `MainActivity` only
    checked permission in `onCreate`, with no `onResume` re-check, so a user
    who granted the permission via system Settings while the app was
    backgrounded (rather than through the in-app dialog) could get stuck on
    the denied screen. `MainActivity.onResume()` now re-checks
    `hasCameraPermission()` against the last-known state every time the
    activity resumes and starts/stops the camera accordingly in both
    directions (denied→granted and granted→revoked), not just at `onCreate`.
    The original "don't ask again"/`USER_FIXED` caveat still applies -- this
    fix re-checks permission *state*, it doesn't add a deep link to system
    Settings for that specific case -- but the core stuck-on-denied-screen
    gap this note flagged is closed.
  - Aside, unrelated to app code: on this device, a system "Android App
    Compatibility" dialog appears on launch warning that
    `libface_detector_v2_jni.so` (ML Kit) and
    `libimage_processing_util_jni.so` (CameraX) aren't 16 KB page-size
    aligned. This is an upstream dependency issue (Google's AARs), not
    something in this skeleton's own code, and only shows because the
    debug build is debuggable — but it's worth knowing about for whenever
    these dependencies get upgraded or a release build is tested on a
    16 KB-page device.
- **Face box + ROI box alignment**: confirmed correctly aligned after the
  two fixes above — the green face box wraps the whole face (hairline to
  chin) and the yellow ROI sits on the forehead as intended, tracking live
  across head movement, tilts, and partial hand occlusion. Before the fix
  the face box was visibly offset right/down, cutting off part of the face.
  ✅ (previously the flagged untested part — now verified and fixed)
- **Live chart**: scrolls in real time while a face is in frame; goes flat
  as old samples age out of the 10 s window when no face is detected (no
  new samples are added, matching the intended behavior). ✅
- **HR/SpO2 fields**: sampled repeatedly over a ~5 minute continuous run
  (screenshots + `pidof` checks at intervals). Values stayed within the
  documented clamped ranges throughout (HR observed 62–88 bpm, SpO2
  observed 95.5–98.5%), updated continuously, and the app process never
  restarted (same pid the entire run). A parallel `adb logcat` capture
  across the same window recorded zero `AndroidRuntime`/`FATAL` entries
  and zero log lines from the app at all beyond the (already-removed)
  diagnostic logging — no crashes, no exceptions. ✅
  - **Important scope note, stated plainly:** this ~5 minute run was against
    `PlaceholderVitalsEstimator.kt` -- **before `RealHeartRateEstimator.kt`
    existed.** It is evidence the camera/UI/permission skeleton doesn't
    crash, not evidence about the real DSP pipeline's stability. The real
    pipeline has its own, separate on-device runs documented in
    [Verification: the HR port](#verification-the-hr-port-segment-4) and
    its follow-ups below (13+ min combined, 5m15s, ~2.5 min, all
    crash-free) -- and a dedicated 15+ minute continuous defense-readiness
    run in
    [`docs/Defense_Readiness_Checklist.md`](docs/Defense_Readiness_Checklist.md).
- **"PLACEHOLDER VALUES" banner**: visible at all times across every state
  tested (camera running, permission denied, no-face). ✅
  (**Superseded** by the HR port below: the single uniform banner has since
  been replaced with two independent per-field status chips, since HR is no
  longer a placeholder and a shared banner would misrepresent it. See
  [Verification: the HR port](#verification-the-hr-port-segment-4).)

All items from the original checklist are now verified rather than
speculative. The one thing still genuinely untested is rotation handling
for the *other* three `rotationDegrees` values (0/180/back-camera-esque
270-vs-90 mirror cases) — this device only ever exercised 270, so if the
app is ever run on a device/orientation that hits 0, 90, or 180, re-check
the overlay alignment there too; the fix should generalize (it's the same
swap-or-not branch either way) but hasn't been observed directly.

## Verification: the HR port (Segment 4)

This section covers the task that replaced `computeHeartRatePlaceholder()`
with a real port of MATLAB's validated HR pipeline. SpO2 is untouched by
this work -- see the section above for what's still fake there.

### What was ported, and the exact parameters used

Read directly from `../matlab/src/` (not from memory/description) before
writing any Kotlin:

- **Detrend** (`filtering/detrendSignal.m` → `BandpassFilter.detrend`):
  cubic (order-3) polynomial least-squares fit, subtracted.
- **Bandpass** (`filtering/bandpassClean.m` → `BandpassFilter.apply`):
  Butterworth **order 2** (effective 4th order after zero-phase filtfilt,
  matching the MATLAB file's own KDoc), cutoffs **0.7-4.0 Hz** normalized by
  a **runtime-measured** `fs` (never hardcoded -- see below for why that
  mattered in practice), designed via bilinear transform of the analog
  prototype (same classic chain MATLAB's `butter()` uses internally), and a
  filtfilt-equivalent (forward pass, reverse, forward, reverse, with
  odd-reflection edge padding to suppress startup transients) -- run as a
  **batch operation over the whole buffered window**, recomputed at most
  once per second, not a causal streaming filter, since zero-phase response
  requires seeing the whole window at once (same reason MATLAB's filtfilt
  call is offline).
- **CHROM/POS** (`pulseextraction/chromCombine.m` + `posCombine.m` →
  `PulseExtraction`): exact formulas (`Xs=3Rn-2Gn`, `Ys=1.5Rn+Gn-1.5Bn`,
  `alpha=std(Xs)/std(Ys)` for CHROM; `S1=Gn-Bn`, `S2=Gn+Bn-2Rn` for POS),
  including the Rn/Gn/Bn normalization judgment call documented in
  `segment4_heartrate/Segment4_LineByLine_Explanation.md`: filtered R/G/B
  are normalized by the **raw (pre-filter)** channels' own means, not the
  filtered channels' own near-zero means. `alpha`/the POS scale factor are
  recomputed fresh per window, never hardcoded. The combined signal is
  re-filtered through `BandpassFilter` again afterward, matching the
  MATLAB pipeline's own re-filter-after-combination step.
- **FFT peak-picking** (`heartrate/fftHeartRate.m` → `HeartRateFft`): FFT
  magnitude spectrum (via JTransforms), band mask applied to **0.7-4.0 Hz
  before** peak search (not an afterthought filter on a global max), peak
  bin converted to bpm. Computed for **both** CHROM and POS; CHROM was the
  primary displayed value at the time this section was written, POS
  `Log.d`'d alongside for comparison. (**Superseded** by the switching
  estimator port -- see
  [CHROM/POS switching estimator port](#chrompos-switching-estimator-port-segment-4-follow-up-4)
  below: the displayed value is now chosen per-reading by a spec'd
  decision rule, not always CHROM. Both raw values are still logged.)
- New dependency: `com.github.wendykierp:JTransforms:3.1`
  (`app/build.gradle.kts`), added now that a real FFT step exists.

### Unit test (no device needed) -- run and result

`app/src/test/java/com/spandan/app/signal/BandpassFilterTest.kt` feeds a
synthetic 1.2Hz sine (in-band, ~72bpm) + 0.2Hz sine (out-of-band) through
`BandpassFilter.apply()` and measures each component's surviving amplitude.
Run via `.\gradlew.bat testDebugUnitTest --tests
"com.spandan.app.signal.BandpassFilterTest"` (JDK 21, see the JDK pitfall
note above). **PASSED**, actual measured numbers:

```
in-band  (1.2Hz): gain = 0.980   (in=1.0000, out=0.9804 -- near-unity)
out-of-band (0.2Hz): gain = 0.0131  (in=1.0000, out=0.0131 -- ~98.7% attenuated)
```

This was checked and passing *before* trusting the filter on real camera
data, same discipline as the MATLAB side's Hoffman dataset sanity check.

### On-device run -- what was actually tested, and the result

**VERIFIED on the same physical Samsung Galaxy A35 (SM-A356E)** used for
the original skeleton verification, over adb, `./gradlew assembleDebug`
(JDK 21 via Android Studio's bundled JBR -- the machine's default `java` on
PATH was JDK 25/Temurin, incompatible with Gradle 8.7's daemon, see the JDK
pitfall note above). Built clean, same harmless `@OptIn` warning as before,
no compile errors (after fixing two self-inflicted issues along the way:
`[b0..bN]`-style brackets in a KDoc comment were misparsed as Kotlin doc
links, and `--` inside XML comments is illegal XML and broke resource
merging -- both fixed, noted here in case they recur).

- **Crash-free, multi-minute run**: installed, launched, and left running
  with a face in frame across two sessions (~13+ minutes combined,
  including a mid-session rebuild+reinstall for the bug below). `pidof`
  stayed constant within each session (no restarts), and a parallel `adb
  logcat` capture across the whole combined session recorded **zero**
  `FATAL EXCEPTION`/`AndroidRuntime` crash entries against 783
  `RealHeartRateEstimator` log lines. ✅
- **Real bug found and fixed via on-device screenshot** (same "check the
  real device, don't guess" discipline as the two `CoordinateMapper` bugs
  above): the app targets SDK 35, where edge-to-edge display is enforced by
  default, and the new HR/SpO2 status chips (see below) were rendering
  *underneath* the device's on-screen navigation bar, clipped and
  unreadable. Fixed by adding a `ViewCompat.setOnApplyWindowInsetsListener`
  in `MainActivity.onCreate` that pads the root layout by the system bars
  inset. Confirmed fixed via a before/after screenshot comparison -- both
  chips fully visible after the fix.
- **Split HR/SpO2 labeling**: confirmed rendering correctly on-device (see
  screenshot check above) -- a green "● LIVE — CHROM/POS + FFT" chip under
  the HR reading, a red "● PLACEHOLDER — not real" chip under the SpO2
  reading, replacing the old single uniform banner. ✅
- **Measured fs, and why "never hardcode it" mattered in practice**: this
  device's real analysis throughput was **~13.1-13.5 Hz**, not the ~30fps
  it'd be easy to assume -- ML Kit face detection appears to bottleneck the
  `ImageAnalysis` throughput on this hardware. Had `fs` been hardcoded to
  30 (as the old placeholder's naive zero-crossing count implicitly
  assumed), every frequency bin would have been mislabeled by roughly 2.2x.
  This is exactly the failure mode the MATLAB side's "never hardcode
  frameRate" discipline (UBFC subjects varying ~28.6-29.8fps) was guarding
  against, now confirmed to matter for a live camera too, and by a much
  larger margin than MATLAB's dataset-to-dataset variation. ✅ (design
  validated by observing it would have been wrong otherwise)
- **CHROM vs POS agreement**: logged side by side every window (`Log.d`,
  see `RealHeartRateEstimator`). Very frequently identical to one decimal
  place (`delta=0.0bpm`), and when they differ, the delta clusters near
  clean multiples of the ~6bpm FFT bin width at this device's measured fs
  (e.g. deltas of 6.0, 11.9, 17.9, 23.8, 29.8bpm observed -- all ~1-5 bin
  widths). This matches, almost exactly, MATLAB's own documented finding in
  `Segment4_LineByLine_Explanation.md` that CHROM and POS report identical
  bpm when their true dominant frequencies fall in the same coarse FFT bin.
  Strong evidence the port's math matches the source, not a coincidence. ✅
- **Manual pulse comparison -- reported honestly, not just "plausible"**:
  the person being measured counted **19 beats in 15 seconds = 76 bpm**
  manual reference. The app's on-screen HR reading was fluctuating
  substantially at the same time -- observed values included 84, 78, 60,
  and 100+ bpm within a short span. The matching `logcat` window confirms
  this: readings across nearby seconds ranged from ~53.8bpm to ~149.9bpm.
  Some individual readings landed close to the 76bpm reference (78, 84 --
  within 2-8bpm); others were off by 20-50+ bpm. **This is a real,
  unresolved accuracy limitation of this on-device build, not swept under
  the rug**: MATLAB's validated full-pool result (CHROM MAE ~9.10bpm,
  r=0.31) was computed on ~80 second UBFC/VIPL clips at ~29fps (~2,362-2,409 samples/clip, ~0.7bpm FFT bin
  resolution). This on-device build's `SignalBuffer` window is 10 seconds
  at the measured ~13.4Hz (~134 samples, ~6bpm FFT bin resolution) --
  roughly **18x fewer samples** than what was actually validated, which is
  the prime suspect for both the coarse bin quantization and the
  window-to-window instability. **Conclusion: the DSP port itself is
  algorithmically faithful (unit-tested filter behavior, CHROM/POS
  agreement pattern matches MATLAB's own documented behavior exactly), but
  this build's short live window means individual on-screen bpm readings
  should not yet be trusted the way MATLAB's validated offline result can
  be.** ⚠️

## Diagnostic: is the ~13.4Hz frame rate steady or bursty? (Segment 4 follow-up)

The manual pulse comparison above (76bpm reference vs. readings ranging
53.8-149.9bpm) left an open question: is that jitter mainly explained by
"only ~134 samples in a 10s window at the measured ~13.4Hz" (a sparse but
roughly steady stream), or is the measured ~13.4Hz actually a **bursty
average** hiding irregular inter-frame gaps -- which would matter a lot
more, because both `BandpassFilter`'s Butterworth design and `HeartRateFft`
assume uniformly spaced samples? This task measured it directly instead of
guessing. **Diagnosis only -- no fix implemented, see recommendation
below.**

### What was measured

Temporary `Log.d`-tagged (`SPANDAN_TIMING`) instrumentation was added at
the point in `MainActivity.handleAnalysisResult` where each `RgbSample`
(already timestamped in `RoiPixelAverager.averageRgb` via
`System.currentTimeMillis()`, see `RgbSample.timestampMs`) is added to
`SignalBuffer`, bounded to the first 45 seconds after app start so logcat
wasn't flooded for the whole session. Also checked: `MainActivity`'s
`ImageAnalysis.Builder()` is configured with
`setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)` (the
only analysis-pipeline config present -- no explicit target frame-rate
range or queue depth). This strategy drops queued frames while the
analyzer is busy and delivers whichever frame is newest once it's free, so
in principle it's a plausible mechanism for bursty timing if ML Kit's
per-frame processing time varies a lot frame to frame. **Not changed in
this task** -- noted only as a plausibility check against the hypothesis.

Captured on the same physical **Samsung Galaxy A35 (SM-A356E)** via
`adb logcat -v time -s SPANDAN_TIMING` over a 45-second window with a real
face continuously in frame (not idle preview). Analyzed with a small
standalone Python script (`re` + `statistics`, no dependencies) parsing
the logged `idx=/ts=/elapsedMs=` triples -- fastest option available, no
device-side computation needed.

### Actual numbers

```
Total sample count:        584
Window duration:           43.49 s (matches the ~45s bounded capture)
Mean inter-sample interval: 74.60 ms   (-> effective fs = 13.41 Hz,
                                          consistent with the ~13.1-13.5Hz
                                          range measured previously)
Std dev:                     4.70 ms
Min interval:                52 ms
Max interval:               140 ms   (single outlier, still <2x mean)
Coefficient of variation:   0.0630   (std/mean)
Gaps > 2x mean (>149.2ms):  0 / 583  (0.00%)

Histogram (10ms buckets):
  50-59 ms:   5
  60-69 ms:  15
  70-79 ms: 517   <- 88.6% of all intervals land here
  80-89 ms:  43
  90-99 ms:   2
 140-149 ms:   1
```

### Characterization

This is a **steady, low-jitter periodic stream, not a bursty one**. CV of
0.063 is low (bursty/irregular timing would show CV well above that, and
likely a heavy right tail), zero gaps exceeded 2x the mean interval, and
88.6% of all 583 intervals fell in a single 10ms bucket centered on the
mean. The one 140ms outlier is a mild single-frame hiccup, not evidence of
clustered/bursty delivery -- there's no second population of large gaps in
the histogram, just one isolated point. `STRATEGY_KEEP_ONLY_LATEST` is
structurally *capable* of producing bursty timing under a variable
processing backlog, but empirically it isn't doing so here -- ML Kit's
per-frame detection latency on this device appears to be fairly
consistent (~70-90ms almost all the time) rather than spiky, so frames
aren't piling up and getting dropped in irregular clusters.

### Recommendation

**The bursty-timing hypothesis is not supported by this capture.** Option
(a) is the better-supported conclusion: timing is roughly steady but
sparse, so **lengthening the buffer window** (more total samples per
window at this same steady ~13.4Hz) is the more appropriate fix, not
resampling onto a uniform time grid. Resampling exists to correct
*irregular* spacing before a fixed-fs filter/FFT are applied to it -- with
CV=0.063 and zero large gaps, the uniform-sampling assumption the
Butterworth filter and FFT depend on is not meaningfully violated here, so
resampling would add real implementation complexity (interpolation
scheme, deciding how to handle gaps during genuine no-face periods) to fix
a problem this capture doesn't show. The 18x-fewer-samples-than-MATLAB's-
validated-clips gap noted in the section above remains the better-
supported explanation for the observed jitter.

**Caveats, stated plainly rather than overclaiming:**
- This is **one 45-second capture on one device, one lighting setup, one
  face**. It rules out the bursty-average hypothesis *for this run*, not
  for all conditions -- a different device, lower light (longer ML Kit/
  sensor exposure latency), or a different face/pose could behave
  differently. If accuracy work continues, it would be worth a second,
  independent capture before fully closing this question.
- This capture only measured timing while a face was continuously
  detected. It does not characterize the gap behavior *at* a no-face ->
  face-detected transition (SignalBuffer simply stops appending during
  no-face, per its existing wall-clock-window design), which is a
  different question from the steady-state timing measured here.
- Window-lengthening's tradeoff (flagged for the team, not decided here):
  slower responsiveness to a changing HR, same tradeoff already flagged in
  the follow-up ideas below -- this diagnostic doesn't change that
  tradeoff, it just weighs in on which fix (window-lengthening vs.
  resampling) the timing data actually supports.

### Follow-up ideas (not implemented here -- out of this task's scope)

- `SignalBuffer`'s window is fixed at 10s and was explicitly out of scope
  to modify for this task. A longer window (closer to MATLAB's ~80s clips)
  would directly improve FFT bin resolution and estimate stability, at the
  cost of slower responsiveness to a changing HR -- worth an explicit
  scope/tradeoff discussion with the team before changing it.
  Note also that `SignalBuffer` only holds `windowSeconds` of *wall-clock*
  time, and at this device's ~13.4Hz measured throughput a 10s window is
  already only ~134 samples -- lengthening the window in wall-clock time
  and/or improving analysis throughput (e.g. profiling why ML Kit face
  detection caps out around 13fps here) would both help.
  **Done in a follow-up task -- see
  [Window-length change: 10s → 25s](#window-length-change-10s--25s-segment-4-follow-up-2)
  below** (raised to 25s, not the full ~80s, as a deliberate live-demo
  tradeoff -- results are mixed, read that section before assuming this
  fully closes the jitter question).
- Temporal smoothing (e.g. a rolling median of the last few CHROM
  estimates) could reduce the on-screen jitter for display purposes, but
  MATLAB's validated pipeline doesn't do this (it produces one number per
  whole clip) -- adding it here would be a real deviation from "faithful
  port," not just a bug fix, so it wasn't added without an explicit
  decision from the team.

## Window-length change: 10s → 25s (Segment 4 follow-up #2)

This task acted on the previous diagnostic's recommendation (steady,
low-jitter timing -- CV=0.063, zero gaps >2x mean -- ruled out bursty
sampling as the cause of on-screen HR jitter, leaving "too few samples per
window" as the better-supported explanation). It **raises the buffer
window from 10s to 25s** and re-tests, rather than assuming the fix would
work.

### 1. Single tunable constant

The window length was already isolated to one constructor parameter
(`SignalBuffer(windowSeconds: Double)`), but its value (`10.0`) was a bare
default-parameter literal, duplicated at the one call site in
`MainActivity.kt` (`SignalBuffer(windowSeconds = 10.0)`) -- two places to
edit, not one. Consolidated into a single named constant,
`SignalBuffer.WINDOW_DURATION_SECONDS` (a `const val` in `SignalBuffer`'s
companion object, with a KDoc explaining what changing it trades off),
and `MainActivity.kt` now references it explicitly
(`SignalBuffer(windowSeconds = SignalBuffer.WINDOW_DURATION_SECONDS)`)
instead of repeating the number. Re-tuning this in the future is now a
one-line change in one file.

### 2. Value and warm-up behavior

Set to **25.0** (~335 samples at the measured ~13.4Hz, vs. ~134 at 10s) --
a deliberate middle ground, not an attempt to match MATLAB's ~80s/~2400-
sample validated clips (which would need ~3 minutes of continuously steady
holding at this device's throughput, impractical for a live demo).

Checked the existing warm-up path (`RealHeartRateEstimator.update()`,
gated independently by `MIN_SAMPLES=60` / `MIN_WINDOW_SECONDS=4.0`,
unrelated constants not touched by this task) and `MainActivity`'s
handling of its `null` return before the window has enough data: it
already displays `"HR: -- bpm"` (`R.string.hr_placeholder_default`)
rather than a fabricated number, with no crash risk. This behavior was
already correct before this task and needed no code change --
`SignalBuffer.kt` was not touched beyond adding the named constant.

### 3. Unit test -- re-run, unaffected as expected

`.\gradlew.bat testDebugUnitTest --tests
"com.spandan.app.signal.BandpassFilterTest"` (JDK 21 via Android Studio's
bundled JBR). **PASSED**, numbers identical to the pre-change run (window
length doesn't touch filter design, confirmed rather than assumed):

```
in-band  (1.2Hz): gain = 0.9804  (unchanged)
out-of-band (0.2Hz): gain = 0.0131  (unchanged)
```

### 4. On-device re-test

**VERIFIED on the same physical Samsung Galaxy A35 (SM-A356E)**, confirmed
attached via `adb devices` before starting. `./gradlew assembleDebug`
built clean (no compile errors), installed via `adb install -r`, launched
via `adb shell am start`. `pidof com.spandan.app` returned the same PID
(`11097`) at the start and end of the test session -- no restarts.

A parallel `adb logcat` capture ran across the whole session. **Zero**
`FATAL EXCEPTION`/`AndroidRuntime` entries, and a broader sweep for
`Exception`/`ANR`/`Crash`/`tombstone` across the entire capture (44 hits
total) found none referencing the app's PID -- all 44 were unrelated
system/Play-Store noise (e.g. `Finsky` package-stats warnings). ✅
crash-free.

**Manual pulse reference**: 21 beats in 15s × 4 = **84 bpm**.

**313 CHROM/POS log lines** captured over a **5m15s** logged session
(22:38:15–22:43:30), comfortably covering many recomputes at the full 25s
window (window size sat at ~24.9–25.0s for nearly the whole capture; the
buffer takes roughly 25–30s of continuous face-in-frame to first reach the
new cap, vs. ~10–15s before).

**Range observed, compared directly against the original 10s-window run**:

| | Original (10s window) | This run (25s window) |
|---|---|---|
| Manual reference | 76 bpm | 84 bpm |
| Full-session range | 53.8–149.9 bpm | 50.3–160.4 bpm |
| Readings within a tight band | not separately reported | 55–120 bpm: 301/313 (96.2%), mean 76.9, median 74.4, stdev 11.6 |

Taken at face value, the **full min/max range did not shrink** -- if
anything the top end is nominally wider this time. But breaking the
session down in time tells a more complete story: **12 of the 313
readings (3.8%) sat above 120 bpm or below 55 bpm, and all 12 clustered
inside one ~90-second stretch (22:41:08–22:42:38)**, not scattered evenly
through the session. That's the timing signature of a single transient
artifact (most likely head/phone movement or a lighting change during that
stretch -- not logged directly, so this is inferred from clustering, not
confirmed by a separate cause) rather than a per-window quantization
problem repeating throughout.

Excluding that one 90-second stretch, the remaining 223 readings ranged
**55.0–105.6 bpm, mean 76.3, stdev 12.6** -- markedly tighter than the
original run's full 53.8–149.9 bpm spread, and bracketing the 84 bpm
manual reference reasonably well (median absolute difference from
reference was noticeably smaller in these calmer stretches than during the
90s excursion). So readings **do visually settle more than before during
calm stretches**, but the session as a whole still produced a comparably
wide occasional excursion, just concentrated rather than spread out.

**CHROM/POS agreement**: FFT bin resolution improved as predicted from the
longer window (~6 bpm bin width at 10s → ~2.4 bpm at 25s, both computed
from measured fs/n). Exact match (`|delta| < 0.1bpm`) occurred in **131 of
313 readings (41.9%)** -- present but not dominant, and not directly
comparable to the original run's qualitative "very frequently identical"
description since that report didn't log an exact percentage. When CHROM
and POS disagreed, deltas still clustered loosely near multiples of the
(now finer) bin width, the same quantization signature as before, just
spread across more distinct multiples than the original's clean
6/12/18/24/30 bpm progression -- consistent with the finer resolution
giving the two methods more distinct bins to land on rather than fewer.

### 5. Honest verdict: partial improvement, not a full fix

**25s helped, but not enough to call the jitter solved, and it did not
fully validate the "insufficient samples" theory on its own.** The
evidence for real benefit: FFT bin resolution improved ~2.5x as designed,
and readings outside one transient-looking 90-second stretch were
noticeably tighter (55.0–105.6 bpm) than the original run's raw spread,
tracking the 84 bpm manual reference reasonably closely in those calmer
periods. The evidence against a full fix: the session's raw min/max range
did not shrink versus the 10s-window run, and a meaningful chunk of that
came from a clustered burst of large excursions that looks more like a
real artifact (motion/lighting) than a sample-count problem -- something a
longer window alone won't fix.

**Recommendation: keep 25s** -- it's a measurable, non-regressive
improvement (better bin resolution, tighter readings in steady stretches,
zero new bugs, unit test unaffected), and the single named constant makes
trying a further increase (e.g. 30–40s) a one-line change if the team
wants to chase the full-range number further. But don't expect a bigger
window alone to fully close the gap: this session's residual instability
looks partly artifact-driven, not purely a sparse-sampling problem, so the
next useful step is probably investigating motion/lighting robustness (or
repeating this test across more sessions to see whether a 90-second
excursion like this one is typical or a one-off) rather than immediately
reaching for a further window increase.

## Does motion or talking explain the clustered bad stretch? (Segment 4 follow-up #3)

The previous section's 90-second excursion (22:41:08–22:42:38, 12/313
readings) was inferred to be a transient artifact "most likely head/phone
movement or a lighting change," but that inference was never actually
tested against a known cause -- it was pattern-matched from clustering
alone. This task ran a second, independent capture with a **deliberately
scripted behavior timeline** (still → talking → moving → still) and
correlated logged face-box motion and CHROM/POS disagreement against it
directly, instead of guessing further from clustering shape.

### What was measured

Temporary `Log.d`-tagged (`SPANDAN_DIAG`) instrumentation, removed again
before finishing (same bounded/removable discipline as the earlier
`SPANDAN_TIMING` diagnostic): added to `RealHeartRateEstimator.update()`
(a `faceBox`/`faceBoxDeltaPx` parameter pair, both defaulting to `null` so
no other call site needed to change) and to
`MainActivity.handleAnalysisResult` (tracking the latest `faceBoxRotated`
and a frame-to-frame Euclidean center-distance delta in rotated-image
pixels). Every HR recompute logged, in one line: `HR_chrom`, `HR_pos`,
`relative_disagreement` (`|chrom-pos| / mean(chrom,pos)`, a percent --
computed from the two bpm values `RealHeartRateEstimator` already produces
internally, not new DSP), the current face-box size/position, and the
frame-to-frame box-center movement delta. `FaceAnalyzer.kt`'s detection
logic itself was not touched.

Captured on the same physical **Samsung Galaxy A35 (SM-A356E)**, `adb
logcat -v time -s SPANDAN_DIAG:D RealHeartRateEstimator:D
AndroidRuntime:E`, with the test subject following a scripted timeline
against the device's own clock (confirmed to match this PC's clock at
capture time, both ~23:10): **still/quiet 23:04:00–23:05:00, talking
23:05:00–23:06:00, moving/tilting 23:06:00–23:07:00, still/quiet
23:07:00–23:09:00+**, preceded by a buffer-fill warm-up period right after
app launch (23:02:24) that was excluded from analysis since the 25s window
was still mixing in pre-test samples.

Both temporary edits were fully reverted (`RealHeartRateEstimator.kt` and
`MainActivity.kt` restored to their exact pre-task content) once the
capture was analyzed -- confirmed by re-running `assembleDebug` clean
afterward and checking `adb logcat` for zero remaining `SPANDAN_DIAG`
lines on the reinstalled build.

### Crash-free

Zero `AndroidRuntime`/`FATAL` entries across the whole ~13-minute logcat
capture. `pidof com.spandan.app` stayed constant at `13761` throughout the
scripted portion (no restarts). ✅

### The behavior-segment breakdown

298 `SPANDAN_DIAG` recomputes fell inside the four scripted segments.
**14/298 (4.7%) landed outside the 55–120bpm band** -- consistent in
magnitude with the prior run's 3.8%, but a materially different *shape*:

| Segment | n | HR range | HR mean | HR stdev | Out-of-band % | mean relative_disagreement | mean face-box Δ |
|---|---|---|---|---|---|---|---|
| 1. Still | 60 | 60.0–129.3 | 81.1 | 18.7 | **6.7%** | 9.0% | 1.3px |
| 2. Talking | 59 | 62.2–157.9 | 84.3 | 14.2 | **1.7%** | 9.7% | 1.7px |
| 3. Moving | 60 | 52.7–91.2 | 76.9 | 11.7 | **3.3%** | 10.8% | 4.0px |
| 4. Still | 119 | 55.0–124.8 | 80.1 | 21.4 | **5.9%** | 10.2% | 0.6px |

The face-box delta column confirms the script was actually followed
(moving shows the highest mean movement, 4.0px vs. ≤1.7px elsewhere) --
but the out-of-band rate does **not** track it: the two **still** segments
had *more* out-of-band readings (6.7%, 5.9%) than either talking (1.7%) or
moving (3.3%). Taken at face value, this segment breakdown argues
**against** motion or talking as the driver in this capture, the opposite
of what the clustering-based inference in the previous section suggested.

### Per-sample correlation, and whether it clustered into one stretch

Checked directly rather than trusting segment averages alone:

```
Pearson r(face-box Δ,  out-of-band flag)        = -0.091   (no correlation)
Pearson r(face-box Δ,  relative_disagreement)   = -0.025   (no correlation)
Pearson r(relative_disagreement, out-of-band)   =  0.191   (weak positive)
Pearson r(face-box Δ,  |chrom - 76bpm|)         = -0.145   (no correlation)
```

**The clustering signature did not reproduce.** The 14 out-of-band
readings did **not** form one continuous stretch this time -- they fell
into four short, scattered bursts of 1–6 consecutive readings (23:04:40–48
in still-1; a single blip at 23:05:37 in talking; 23:06:43–44 in moving;
23:08:01–12 in still-2), separated by 49–77 seconds of clean in-band
readings each time, spread across **all four** segments rather than one.
So even setting aside the segment-average result above, the temporal
*pattern* itself argues against a single sustained episodic trigger in
this particular capture.

One nuance worth flagging for later: of the 14 out-of-band readings,
roughly half showed clearly elevated CHROM/POS disagreement (21–72%) while
the other half showed low/near-zero disagreement (0–13%) -- i.e. CHROM and
POS *agreed* with each other on the same wrong number. That second group
can't be explained by "the two estimators picked different FFT peaks"; it
points at something upstream of the CHROM/POS split (e.g. the raw RGB
signal itself for that window), which is a different failure mode than
what a CHROM/POS switching rule (Part B, see below) could ever fix, even
if implemented.

### Honest conclusion: inconclusive, and the two runs disagree

**This capture does not confirm the motion/talking hypothesis, and it
does not reproduce the single-continuous-stretch pattern from the
previous run.** The out-of-band rate stayed in the same ~4–5% ballpark
across both runs, but its *distribution in time* was completely
different: one sustained ~90-second block previously, versus four small
scattered 1–6-reading bursts spread through calm and active segments
alike this time, with no supporting per-sample correlation to face
movement (r≈-0.09) and only a weak one to CHROM/POS disagreement
(r≈0.19). **Neither run should be treated as the settled answer** -- the
honest reading is that a single ~90-second artifact and a single scripted
motion/talking test are two different capture conditions
(lighting/hand-holding/exposure were not controlled or logged in either
one), and one data point in each direction isn't enough to call this
closed either way.

**No fix was implemented (as scoped).** Because no clear, repeatable
trigger emerged from this capture, inventing a targeted fix now (e.g. a
motion-based reject window) would be guessing at a threshold with no
evidence behind it. **Recommendation for the team:** run a few more
scripted captures like this one -- adding logging for lighting change and
momentary occlusion specifically, since neither was in this script and
both remain untested candidate triggers -- before deciding whether a
motion/lighting reject window is worth building, and consider logging
camera auto-exposure/auto-white-balance state alongside face-box motion
next time, since the "CHROM and POS agree on the same wrong answer"
sub-pattern above suggests the cause for at least some of these readings
sits upstream of the CHROM/POS choice entirely.

## CHROM/POS switching estimator port (Segment 4 follow-up #4)

Step 4 of this task's scope was to check for a
`Android_HR_Switching_Port_Spec.md` MATLAB→Android port spec (the
convention used by the existing Segment 2–6 guideline docs under
`../segment*/`) before porting anything. **It did not exist when Part A
above was written -- a re-check partway through this task found it had
since landed at `../docs/Android_HR_Switching_Port_Spec.md`** (the
parallel MATLAB "Task I"/"Task J" work referenced in that spec had
finished in the meantime). Read in full before writing any Kotlin, and
followed exactly -- no reinterpreted threshold, no invented decision
rule.

### What the spec says, and what was ported

Per the spec: for a reading with `HR_chrom`/`HR_pos` already computed,
`relative_disagreement = abs(HR_chrom - HR_pos) / mean(HR_chrom, HR_pos)`
(a fraction). If that's **< 0.2927 (29.27%)**, display CHROM; otherwise
display POS. The 29.27% threshold is not arbitrary -- per the spec it's
the lower edge of a genuine 9.69-point gap in the sorted
relative_disagreement distribution across the project's full 112-subject
UBFC+VIPL pool, separating a dense "methods agree" mass from a sparse
"methods diverged" tail.

Implemented in `RealHeartRateEstimator.kt` exactly as specced:
`relative_disagreement` is computed from the `chromResult.bpm`/
`posResult.bpm` values the pipeline already produces each recompute (no
new signal processing, per the spec's own implementation note), and
`update()` now returns the switched value (`Estimate.displayedBpm`)
instead of always `chromBpm`. `Estimate` still carries `chromBpm` and
`posBpm` (the raw, un-switched values) plus the new
`relativeDisagreement`/`usedPos` fields, and the per-recompute `Log.d`
line now reports all of it -- `HR_chrom`, `HR_pos`, `relative_disagreement`,
and which one got displayed -- so the switch's behavior can be audited
against the raw CHROM-alone/POS-alone values exactly as before. The
spec's two caveats (Sections 6–7: the rule is blind to CHROM/POS agreeing
on the same *wrong* answer, and even when it fires it only picks the
better estimate ~62.5% of the time on the validation pool) are the
spec's, not re-litigated here -- see the spec doc directly.

### Unit test -- re-run, unaffected as expected

`BandpassFilterTest` doesn't exercise `RealHeartRateEstimator` and was
re-run anyway as a sanity check: **PASSED**, same numbers as every prior
run (`in-band gain=0.9804`, `out-of-band gain=0.0131`) -- the switch is a
post-processing decision on already-computed bpm values, it doesn't touch
filter design.

### On-device re-test

**VERIFIED on the same physical Samsung Galaxy A35 (SM-A356E).**
`./gradlew assembleDebug` built clean, no compile errors. Installed via
`adb install -r`, launched via `adb shell am start`. Ran with a face in
frame for ~2.5 minutes; `pidof com.spandan.app` stayed constant
throughout (no restarts), and the parallel `adb logcat` capture recorded
**zero** `AndroidRuntime`/`FATAL` entries against 156
`RealHeartRateEstimator` log lines. ✅ crash-free.

**The switch fires on real data and respects the threshold boundary
correctly** -- spot-checked directly against the logged
`relative_disagreement` values: readings at 27.85% stayed on CHROM
(below 29.27%), readings at 31.58% and above switched to POS, exactly as
the decision rule specifies with no off-by-one or rounding slip at the
boundary. Over the full ~2.5-minute capture, the switch selected POS for
**26 of 156 readings (16.7%)** -- a higher fire rate than the spec's
~7.14%-of-subjects figure, but that's expected: this is one continuous
live capture with this build's known window-to-window jitter (see
sections above), not a like-for-like comparison to MATLAB's per-subject
whole-clip statistic.

**Manual pulse comparison -- sanity check only, not a re-validation**:
20 beats in 15s = **80 bpm** manual reference. The final ~10 seconds of
displayed (post-switch) readings ranged **74.2–105.6 bpm**, bracketing
the reference loosely but still showing the same order of jitter this
build has had since the HR port -- the switch is not a jitter fix (nor
was it meant to be; see the spec's Section 8 note that this addresses one
specific disagreement-based failure mode, not general accuracy). Not
obviously broken, which is all this step asked for.

**Recommendation:** the port is done and behaving per spec. Because the
switch is validated only against the same MATLAB pool the threshold was
tuned on (the spec's own Section 5 caveat), and because Part A's own
diagnostic above independently found cases where CHROM/POS *agree* on a
wrong value (something this rule is structurally blind to per the spec's
Section 6), don't present this as a general accuracy fix on-device
either -- it's one more useful signal alongside the existing "LIVE" chip,
not a resolution of the window-to-window jitter documented throughout
this README.

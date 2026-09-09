# Segment 7 Task G — Throughput Profiling (ACTION C1/C2)

**Update — real measurement captured.** A previous attempt on a different
machine was blocked before any APK could be built (that machine's own
JVM-level AF_UNIX/`Selector.open()` failure, unrelated to this project's
code — see "Prior blocked attempt" below for the full original account,
kept for the record). On the current machine that blocker did **not**
reproduce: the build succeeded, `ProfilingFaceAnalyzer` was temporarily
wired into `MainActivity.kt` in place of `FaceAnalyzer`, installed on a
physical device (Samsung Galaxy A35, SM-A356E, Android 16/API 36), and run
for a live ~100-second capture with a face continuously in frame. Section 1
below is that real measurement. Section 2 (the original code-structure
inference) is kept below it, now confirmed rather than superseded — see the
comparison at the end of Section 1.

## 1. Real measurement (Galaxy A35, Android 16, front camera, PERFORMANCE_MODE_FAST)

Captured via `adb logcat -s ProfilingFaceAnalyzer:D`, parsing the
per-frame `SPANDAN_PROFILE` lines. Two views of the same run:

**Full run (0.98s–100.56s, 1341 frames, 98.1% face-found):**

| Phase | mean | min | max | p90 |
|---|---|---|---|---|
| detectMs | 71.59 | 53.29 | 90.61 | 74.33 |
| roiMs (face-found frames only) | 0.51 | 0.18 | 5.35 | 0.50 |
| otherMs | 0.64 | 0.23 | 6.15 | 0.87 |
| **totalMs** | **72.73** | 56.90 | 100.52 | 75.66 |

Effective throughput: **13.46 fps** over the full run.

**Steady-state last 60s (807 frames, 100% face-found, face held still in frame):**

| Phase | mean | min | max | p90 |
|---|---|---|---|---|
| detectMs | 71.84 | 67.69 | 87.53 | 74.16 |
| roiMs | 0.43 | 0.36 | 0.67 | 0.48 |
| otherMs | 0.64 | 0.27 | 6.15 | 0.82 |
| **totalMs** | **72.91** | 68.44 | 89.01 | 75.32 |

Effective throughput: **13.44 fps**, steady state.

**What this confirms:** ML Kit `detector.process()` is **~98.5% of the
per-frame cost** (71.84ms of 72.91ms mean total). ROI/coordinate-mapping/
pixel-averaging is negligible (0.43ms mean, <1% of the frame budget).
"Everything else" is also negligible (0.64ms mean). This is a real
measurement, not an inference — it quantitatively confirms Section 2's
code-structure reasoning below (which had predicted exactly this
ordering) and the existing `android/README.md` "Diagnostic" section's
prior inference that ML Kit face detection bottlenecks `ImageAnalysis`
throughput. The measured **13.4-13.5 fps** also matches that document's
previously-inferred "~13.4Hz" almost exactly.

**Capture method, for reproducibility:** `MainActivity.kt`'s
`bindUseCases()` had its one `FaceAnalyzer { ... }` line temporarily
swapped to `ProfilingFaceAnalyzer { ... }`, rebuilt (`gradlew.bat
assembleDebug`), installed (`adb install -r`), and launched. Logcat was
cleared (`adb logcat -c`) at launch, and the device held with a face
continuously in frame during a live camera session; the buffer was then
dumped with `adb logcat -d -s ProfilingFaceAnalyzer:D` and parsed offline
(matching the per-frame-line-parsing approach this file's own class doc
comment in `ProfilingFaceAnalyzer.kt` recommends over relying on the
crude running `dumpSummary()` aggregate). Immediately after the capture,
the one-line swap was **reverted** back to `FaceAnalyzer` and the app
rebuilt/reinstalled — the "bounded/reverted diagnostic" discipline this
file already called for (see the now-superseded wiring note below), same
as `android/README.md`'s existing `SPANDAN_TIMING`/`SPANDAN_DIAG`
captures. `MainActivity.kt`, `FaceAnalyzer.kt`, `RoiPixelAverager.kt`, and
`RoiCalculator.kt` are all unchanged from before this capture.

## Prior blocked attempt (different machine, kept for the record)

**On that machine, this task did NOT produce a real measured per-frame
timing breakdown.** The build+run chain was blocked at the very first step
(`./gradlew.bat assembleDebug`, before any APK, emulator, or device was
involved) by an environment-level JVM defect, confirmed to be unrelated to
this project's code.

### Environment check (all passed)

- `android/local.properties` → `sdk.dir=G:/Android_Studio_SDK`. Verified to
  exist with real contents: `platform-tools/` (adb.exe present),
  `platforms/` (android-35, android-36.1), `build-tools/` (34.0.0, 35.0.0,
  36.1.0, 37.0.0), `emulator/` (emulator.exe present).
- `adb.exe devices` → **no devices/emulators attached** (empty list).
- `emulator.exe -list-avds` → **`Pixel_7` present**, as expected.
- JDK: `C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot\bin\java
  -version` → `openjdk version "17.0.20"` (Temurin), a version Gradle 8.7
  supports.

### The actual blocker: `assembleDebug` fails before any daemon starts real work

```
cd android && JAVA_HOME=".../jdk-17.0.20.8-hotspot" ./gradlew.bat assembleDebug --no-daemon
```

fails immediately, both from the Bash tool and independently from
PowerShell (ruling out a shell-specific quirk), with:

```
FAILURE: Build failed with an exception.
* What went wrong:
java.io.IOException: Unable to establish loopback connection
```

Full stack trace (`--stacktrace`) traces this to Gradle's daemon-connection
socket setup, but the root cause bottoms out inside the JDK itself:

```
Caused by: java.net.SocketException: Invalid argument: connect
	at java.base/sun.nio.ch.UnixDomainSockets.connect0(Native Method)
	at java.base/sun.nio.ch.UnixDomainSockets.connect(UnixDomainSockets.java:148)
	...
	at java.base/sun.nio.ch.PipeImpl$Initializer$LoopbackConnector.run(PipeImpl.java:133)
	at java.base/sun.nio.ch.WEPollSelectorImpl.<init>(WEPollSelectorImpl.java:78)
	at java.nio.channels.Selector.open(Selector.java:295)
```

**Confirmed this is not a Gradle problem at all.** A minimal standalone
Java program with nothing but `Selector.open()` was compiled and run
directly with this same JDK, with no Gradle involved:

```java
import java.nio.channels.Selector;
public class SelTest {
  public static void main(String[] a) throws Exception {
    Selector s = Selector.open();
    System.out.println("Selector opened OK: " + s);
  }
}
```

This throws the **identical** `IOException: Unable to establish loopback
connection` / `UnixDomainSockets.connect0` stack trace. Since JDK 16, the
JVM's default NIO `Selector` implementation on Windows uses an AF_UNIX
domain socket internally (for its wakeup pipe), regardless of which
`SelectorProvider` is requested — a forced
`-Djava.nio.channels.spi.SelectorProvider=sun.nio.ch.WindowsSelectorProvider`
was also tried and hit the exact same `PipeImpl` code path and failure.
`ping 127.0.0.1` and DNS resolution of `localhost` both work fine on this
machine, so plain TCP loopback is not the issue — specifically **AF_UNIX
loopback socket support is unavailable in this execution environment**.

**Impact: any JVM process on this machine that calls
`java.nio.channels.Selector.open()` fails**, which is what Gradle's daemon
(even in "single-use" `--no-daemon` mode, which still spawns one) needs
internally for its client/daemon socket protocol. This is a property of
this specific execution environment (almost certainly a sandboxed/
containerized shell around an otherwise-normal-looking Windows 11 host —
plain networking primitives like TCP/ping/DNS work, but this one JVM
socket primitive does not), not of the Spandan project, its Gradle
configuration, or its Kotlin code. Enabling/fixing AF_UNIX socket support
at the OS level would itself be a system-settings change, which is outside
what this task is permitted to do even if a specific fix were known.

**Because the build itself never produces an APK, there is nothing to
install on the `Pixel_7` AVD or a physical device, so booting the emulator
was correctly skipped** per this task's own guidance ("if gradle build
itself fails ... there's no point booting the emulator").

### Net result (on that other machine)

No APK was built. No emulator was booted. No device was attached. No
camera feed, no ML Kit face detection, no logcat capture ever ran. This
was the complete, honest account of the build/run chain and exactly where
it stopped — now superseded by the real capture in Section 1 above, run on
a different machine where this blocker did not reproduce.

## 2. Section 2 — CODE-STRUCTURE INFERENCE ONLY (explicitly NOT a measurement)

Everything below is derived from reading
`android/app/src/main/java/com/spandan/app/camera/FaceAnalyzer.kt`,
`RoiPixelAverager.kt`, and `RoiCalculator.kt`, plus the already-existing
(also code-structure-based-until-now) attribution in `android/README.md`'s
"Diagnostic" section. **None of the numbers in this section were captured
on a running app in this task.** They are typical-cost reasoning about the
operations each line performs, offered only because C1 was blocked and the
task instructions permit a clearly-labeled inference as a substitute.

- **ML Kit `detector.process(inputImage)` (`FaceAnalyzer.kt` line 73)** is
  called once per frame, synchronously triggered from the `ImageAnalysis`
  callback thread, and the frame is not closed (`imageProxy.close()`,
  lines 83/104/109) until its listener fires — so `ImageAnalysis`'s
  `STRATEGY_KEEP_ONLY_LATEST` backpressure means the next frame cannot even
  begin until this call's listener returns. A full-frame CNN-style face
  detector (even ML Kit's `PERFORMANCE_MODE_FAST` mode, `line 39`) doing
  a real inference pass per frame is, by a wide margin, the most
  expensive category of operation in this callback compared to the
  arithmetic-only work below. This is very likely the dominant cost, but
  this is an inference from what kind of operation it is, not a measured
  number.
- **ROI crop + RGB averaging (`RoiPixelAverager.averageRgb`,
  `RoiCalculator.foreheadRoiFrom`, `CoordinateMapper.rotatedRectToSensorRect`)**
  is a nested pixel loop (`RoiPixelAverager.kt` lines 51-79) over the
  cropped forehead-ROI sub-region only (not the full frame), already
  stride-2 subsampled in both axes (`SAMPLE_STRIDE = 2`, line 25), doing
  plain integer/float arithmetic (BT.601 YUV→RGB conversion) per sampled
  pixel with no allocation inside the loop. The ROI is a small fraction of
  the full sensor frame (a `0.30-0.70` × `0.10-0.30` crop of the detected
  face box, itself usually well under the full frame — see
  `RoiCalculator.kt`). This is a much smaller amount of arithmetic work
  than a full-frame ML-inference pass, so it is likely a minor contributor
  by comparison — again, an inference from operation type and data size,
  not a measurement.
- **"Everything else"** (`InputImage.fromMediaImage` construction,
  rotated-dimension bookkeeping, the `onResult()` callback into
  `MainActivity`, `imageProxy.close()`) is a handful of field reads/int
  arithmetic and one function-pointer invocation — expected to be
  negligible next to either of the above, though this too is inference,
  not measurement.

This reasoning is **consistent with**, but does not newly confirm, the
existing `android/README.md` "Diagnostic" section's own already-labeled
inference ("ML Kit face detection appears to bottleneck the `ImageAnalysis`
throughput on this hardware") — this task adds no new evidence for or
against that claim, because C1 could not run.

## 3. ACTION C2 — proposal for raising effective fs toward ~25-30 Hz

Originally based only on the Section 2 code-structure inference; now
**backed by the Section 1 real measurement**, which confirms detection is
~98.5% of the per-frame cost. The smallest-footprint change most likely to
help:

**Proposed: run full ML Kit detection every Nth frame (e.g. N=2 or 3),
and reuse the last known face box (or a cheap tracker) on the
in-between frames.**

- Rationale: if the per-frame budget really is dominated by one expensive,
  asynchronous ML Kit call (Section 2's inference), the direct lever with
  the best ratio of expected throughput gain to implementation risk is to
  simply call that expensive operation less often, not to make each call
  individually faster (which risks an accuracy/robustness trade against a
  model that's already at `PERFORMANCE_MODE_FAST`) or to change what
  `ImageAnalysis` delivers (resolution changes touch `RoiPixelAverager`'s
  pixel-index math and `CoordinateMapper`'s scale math — larger blast
  radius for the same goal).
- Sketch: keep a `lastFaceBoxRotated: Rect?` and a frame counter in the
  analyzer. On frames where `frameCounter % N != 0`, skip
  `detector.process(...)` entirely and reuse `lastFaceBoxRotated` directly
  for the ROI/averaging step (accepting that the face box goes briefly
  stale between real detections — bounded by N frames at ~75ms/frame,
  i.e. ~150-225ms of staleness for N=2-3, comparable to normal head-motion
  speed for a forehead ROI). On frames where a real detection does run,
  overwrite `lastFaceBoxRotated`. This needs no new dependency (no optical
  flow / KLT tracker — `matlab/docs/Segment7_Task_D_Landmark_ROI.md`
  already found a KLT-based tracked-ROI approach net-regressed the MATLAB
  pipeline's accuracy, a caution against reaching for a heavier tracker
  here too) and is a small, local, easily-revertable change confined to
  the analyzer class.
- Expected effect: Section 1's real measurement confirms the premise this
  projection depends on (detection genuinely dominates: 71.84ms of 72.91ms
  mean total, i.e. ~98.5%). Running detection every Nth frame should
  therefore scale effective fs roughly toward `N ×` the current measured
  **13.44 fps** steady-state figure, which could plausibly approach the
  25-30Hz target for N=2-3. This is still a projection, though now
  grounded in a real baseline measurement rather than an inference — the
  actual post-change number should still be re-measured with the same
  `ProfilingFaceAnalyzer` capture method once N-frame skipping is
  implemented, since skipped-frame ROI reuse could itself add small costs
  (e.g. slightly more `otherMs`) not present in this baseline.
- Alternative candidates considered, per this task's brief, and why the
  above is preferred absent real measurements: a lower ML Kit
  accuracy/performance mode is not available to lower further (the app
  already uses `PERFORMANCE_MODE_FAST`, the fastest of ML Kit's two
  modes); a smaller analysis resolution would help only if per-pixel cost
  (detection's internal image scaling, or `RoiPixelAverager`'s loop) is
  the bottleneck rather than fixed per-call model-inference overhead, and
  Section 2's reasoning suggests the latter is more likely from the
  ML-Kit-does-real-inference-per-call structure of the code, so resolution
  reduction is offered as a fallback rather than the primary proposal. If
  a future real Section-1 measurement instead shows ROI/averaging is the
  actual bottleneck (contrary to Section 2's inference), the right
  follow-up would be different — most likely widening
  `RoiPixelAverager.SAMPLE_STRIDE` further, or restricting the loop bounds
  more tightly — and should be re-derived from that real data rather than
  from this document's untested guess.

**Not implemented, per this task's scope** — this section is a proposal
only.

## 4. Explicit scope boundary respected

Per this task's instructions, `adaptiveHarmonicFilter`, `ensembleAverageBeats`,
and `notchDetectIEM` were **not** ported to Android, and no dicrotic-notch
waveform display was added anywhere in this app. Nothing in this task
touched HR/SpO2 display logic, `SignalBuffer.kt` (its `WINDOW_DURATION_SECONDS
= 25.0` was read for context only, not modified), `FaceAnalyzer.kt`,
`RoiPixelAverager.kt`, `RoiCalculator.kt`, or `MainActivity.kt`.

## 5. Files added by this task (all new; `MainActivity.kt` temporarily modified and reverted for the capture)

- `android/app/src/main/java/com/spandan/app/camera/ProfilingFaceAnalyzer.kt`
  — `ImageAnalysis.Analyzer` implementation, structurally identical to
  `FaceAnalyzer.kt` (same detector config, same largest-face rule, same
  ROI/coordinate-mapping/averaging calls, calling those same existing
  `RoiCalculator`/`CoordinateMapper`/`RoiPixelAverager` objects rather than
  reimplementing them), with `SystemClock.elapsedRealtimeNanos()` timing
  split into `detectMs` / `roiMs` / `otherMs` per frame, logged via
  `Log.d("ProfilingFaceAnalyzer", ...)` per frame plus a `dumpSummary()`
  method for crude running aggregates. **Compiled and run for real on a
  physical device — see Section 1.**
- This file (`android/docs/Segment7_Task_G_Throughput_Profiling.md`).
- `android/app/src/main/java/com/spandan/app/MainActivity.kt` — the one
  analyzer-construction line was temporarily changed to
  `ProfilingFaceAnalyzer { ... }` for the Section 1 capture, then
  **reverted back to `FaceAnalyzer { ... }`** immediately after, and the
  app rebuilt/reinstalled to confirm the revert. The file's committed
  state is unchanged from before this task.

**Wiring note — now done (superseded).** The one-line swap this note
previously described as deliberately not-yet-made was carried out for the
Section 1 capture: `MainActivity.kt`'s `bindUseCases()` line was changed
to `val analyzer = ProfilingFaceAnalyzer { result -> ... }`, run for a live
~100-second session (60s of it steady-state) with a face in frame, the
`SPANDAN_PROFILE` lines captured via `adb logcat -s
ProfilingFaceAnalyzer:D` and parsed offline (the more rigorous option, per
this file's own class doc comment, over the crude running `dumpSummary()`
aggregate), then reverted back to `FaceAnalyzer { ... }` — the exact
bounded/reverted-diagnostic discipline this note originally called for.

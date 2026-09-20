# Spandan — Master Project Handoff

*Generated 2026-09-14 (Cowork session), consolidated from the repo's own
`SESSION_HANDOFF.md`, `README.md`, `android/README.md`, project memory, and
the EEE 312 course files. This is a **self-contained snapshot**, written so
someone with only this file — on a completely different computer, with no
access to the original machine — can understand the whole project and
resume work. It is not a replacement for the repo's own living
`SESSION_HANDOFF.md`, which stays the actively-maintained, task-by-task
source of truth once you have the repo — this file is the comprehensive
"big picture + how to get set up" companion to it.*

---

## 0. How to use this document

If you are a fresh Claude session (or a human) opening this project cold,
read in this order:

1. **This file**, top to bottom — gets you full context with zero repo access.
2. `SESSION_HANDOFF.md` (repo root, once you have the repo) — the
   maintained, task-by-task current-state-and-todo log. Read its "Current
   State" and "Active Work Queue" sections; they are more current than
   anything below by definition.
3. `matlab/docs/Spandan_Final_Pipeline_Report.md` — the finished, adopted
   pipeline as a clean technical report (not a work log).
4. `README.md` and `android/README.md` — architecture + folder-structure
   reference.
5. Any specific `docs/Segment*_Task_*.md` — only when you need the full
   derivation/evidence behind one specific decision.

Everything in this file was true as of **2026-09-14** (through Segment 17).

---

## 1. Who / what / why (30-second version)

**Abrar Jawad** — 3rd-year (3-1) EEE undergraduate at BUET (Bangladesh
University of Engineering and Technology), Section A1, Group 05 — is
building **Spandan** ("heartbeat/pulsation" in Bengali) as his **EEE 312
(Digital Signal Processing I Laboratory) group design project**, supervised
by **Prof. Dr. Md. Kamrul Hasan**.

**Group collaborators on Spandan**: Abrar Jawad, **Ramis Isfar**,
**Bayezid Rahman**, and **Lubaba Tasnia Khan**.

**Goal**: estimate heart rate (HR) and blood-oxygen saturation (SpO2) from
ordinary facial video, with no contact sensor, using **classical
(non-deep-learning) DSP** in MATLAB — then port the validated pipeline to a
real Android app (and an experimental iOS app).

**Status in one line**: MATLAB pipeline implemented and validated across two
public datasets (112+ subjects); Android app is feature-complete and
defense-ready, verified on physical hardware; iOS app exists but is
CI-verified only (no physical iPhone testing yet); a self-collected
Bangladeshi test set has not yet been started.

---

## 2. Course context (why this project exists)

- **Course**: EEE 312 — Digital Signal Processing I Laboratory, BUET Dept. of
  EEE. Compulsory, sessional, 1.5 credit. Companion theory course: EEE 311
  (Digital Signal Processing I).
- **Structure**: Experiments 1–5 (sampling/quantization, time-domain
  analysis, Z-transform, DTFS/DTFT/DFT, FIR filter design) plus a
  **term-long design project** that groups propose, present, and demonstrate.
  Spandan is that design project.
- **Assessment**: class participation 10%, continuous assessment 20%, final
  exam 70%.
- **Supervisor requirements** (given at the project progress presentation):
  Dr. Hasan strictly asked the team to improve rPPG **signal quality** — a
  waveform as close to a real PPG as possible, with a visible dicrotic notch,
  and stable — and to back changes with literature. Defects he identified in
  an earlier waveform: very few dicrotic notches (only in places); most
  notches cut off at the top; the few visible notches appeared
  reversed/inverted. Improving exactly this (the "Branch 2" / morphology work
  below) has been the throughline of Segments 6–17.

---

## 3. The repo

- **GitHub**: `github.com/Thunder-Bird-007/spandan_contactless_vital_sign`,
  branch `main`.
- **Git practice**: commit-per-segment directly on `main`. No feature
  branches. As of this snapshot the latest commit is `cfdf54d` (Segment 16);
  Segment 15 landed as `72105ca`.
- **Releases**: the GitHub Releases page (`.../releases/latest`) always
  carries the newest built Android APK and the unsigned iOS IPA — see §6 for
  install instructions.
- `data/raw/`, `data/processed/`, `data/self_collected/`, and `results/` are
  **git-ignored** — this is an academic repo and shouldn't carry gigabytes of
  video/dataset content in its history. **This means a fresh clone on any
  machine starts with no datasets** — you must extract/download them
  yourself before batch scripts will run (see §9 for exactly what and where
  from).

---

## 4. Architecture

Two branches off one shared ROI extraction (`roi/extractROISignals.m`):

- **Branch 1 — production HR + SpO2.** Narrow 0.7–4 Hz band. This is what
  ships in the Android app.
- **Branch 2 — waveform morphology / dicrotic notch.** Wide 0.5–8 Hz band +
  a harmonic-comb filter. This is the branch the supervisor's feedback is
  aimed at. **Never ported to Android**, by deliberate, repeatedly-reconfirmed
  scope decision (regression risk vs. available runway before defense).

**These two branches are deliberately not merged** — the wide-band /
harmonic-comb filtering Branch 2 needs measurably breaks Branch 1's HR
accuracy (one VIPL subject's CHROM jumped 69.4→140.8 bpm under it when tried
combined).

### Pipeline stages (both branches share 1)

1. **Face detection + ROI extraction** — detect the face per frame, crop a
   forehead ROI (production/Android), spatially average pixel intensities per
   channel → three 1-D signals R(t), G(t), B(t). (Multi-region/cheek ROI
   exists as an experimental, gated, non-default option — see §7.)
2. **Denoise + detrend + bandpass filter**:
   - **DWT wavelet-shrinkage denoising** (`filtering/waveletDenoise.m` — db4,
     3-level, Donoho-Johnstone universal soft-threshold) — **default `true`**
     as of 2026-09-13, both MATLAB and Android (`WaveletDenoise.kt`).
   - Detrend, then bandpass: **0.7–4 Hz** (Branch 1) or **0.5–8 Hz wide /
     0.6–6 Hz mid** (Branch 2, `bandpassMorphology.m`'s `bandMode` argument;
     production stays on `wide`).
3. **CHROM / POS combination** — published, motion-robust pulse-extraction
   algorithms combining the three channels (`pulseextraction/chromCombine.m`,
   `posCombine.m`). **POS is the better performer** on this project's own
   pooled data (see §8) and has a proven mechanistic reason why (see §10,
   "isochromatic pulsation").
4. **FFT → heart rate** — FFT the combined pulse signal, find the dominant
   frequency in the 0.7–4 Hz search band, convert to bpm
   (`heartrate/fftHeartRate.m`).
5. **SpO2 estimation** — AC/DC ratio-of-ratios on Red/Blue channels (camera
   has no IR channel; Blue substitutes for Infrared, a known published
   approximation) → linear calibration (A = 96.4763, B = −0.41595, formula
   `SpO2 = A − B·R`, uncentered, sign-corrected per Dr. Hasan's
   clarification). **Honestly documented as weak**: loses to a
   predict-the-training-mean baseline on all honest tests, due to
   insufficient physiological SpO2 variance in healthy subjects plus a
   cross-camera Simpson's-paradox offset — a data limitation, not a code bug.
6. **Branch 2 morphology filtering** — `adaptiveHarmonicFilter.m` (ABPF, a
   verified real port of Moço/Stuijk/de Haan, *Sci Rep* 8:8501, 2018), now
   wrapped by **`harmonicFilterConfidenceGate.m`** (production default as of
   Segment 14): keep ABPF wherever its own notch confidence already clears
   this project's 0.3 bar; substitute `harmonicSelectiveGaussianFilter.m`
   (alpha=0.15) only where ABPF fails. Set
   `opts.useConfidenceGate=false` on `estimateVitalsAndMorphology.m` to get
   the pre-2026-09-13 ABPF-only behavior exactly.
7. **Validation** — leave-one-subject-out (LOSO) cross-validation (MAE, RMSE,
   Pearson r, Bland-Altman) plus, as of Segment 11, a ground-truth-free
   fidelity metric: **cross-ROI PLV** (`validation/computeCrossROIPLV.m`).
8. **Self-collected test set** (pipeline stage 7 in the original plan) —
   classmates on video with a real pulse-oximeter ground truth, held out from
   the public training data — **not yet started**.
9. **Android app** — real-time on-device HR/SpO2 display, a faithful port of
   Branch 1 only. **Implemented and defense-ready**, not a future phase.

The real orchestrator both branches actually run through is
`pipeline/estimateVitalsAndMorphology.m` (not the older, unimplemented
`estimateVitals.m` stub, and not the VIPL-integration batch scripts, which
are Branch-1-only).

---

## 5. Repo folder structure

```
spandan/
  SESSION_HANDOFF.md      <- the living, actively-maintained entry point (READ FIRST once you have the repo)
  README.md                <- architecture + folder reference + download/install instructions
  LICENSE
  matlab/
    startup.m               <- adds all src/ subfolders to the MATLAB path — run this first
    src/
      io/                    - loadUBFCVideo.m, loadGroundTruth.m
      roi/                   - extractROISignals.m (multi-region as of Task N; Android uses only default forehead mode)
      filtering/             - bandpassClean.m, detrendSignal.m, waveletDenoise.m (DEFAULT ON), resampleSource2CubicSpline.m
      pulseextraction/       - chromCombine.m, posCombine.m, cpaceProjection.m (gated, NOT default),
                                cpaceEigenExtract.m, cpaceHomodyneNormalize.m (gated, NOT default)
      heartrate/             - fftHeartRate.m, windowedHeartRate.m
      spo2/                  - ratioOfRatios.m, calibrateSpO2.m (ported live to Android)
      morphology/            - adaptiveHarmonicFilter.m (ABPF), harmonicSelectiveGaussianFilter.m (gated),
                                harmonicFilterConfidenceGate.m (DEFAULT ON, wraps the two above), notchDetectIEM.m,
                                fixPolarity.m, bandpassMorphology.m, ensembleAverageBeats.m — NOT ported to Android
      validation/            - runLOSO.m, computeMetrics.m, blandAltman.m, computeCrossROIPLV.m (adopted standing metric),
                                residualAdaptiveKalmanHR.m (tested, rejected), computeRegionSwitchingEstimateWeighted.m (pilot)
      pipeline/              - estimateVitalsAndMorphology.m <- the REAL orchestrator; estimateVitals.m is an unused stub
    scripts/                 - run_pipeline_demo.m, batch_process_dataset.m, run_spandan_interactive.m (single-file
                                interactive demo, self-locates matlab/src/ via addpath — see §7), plus one
                                run_segmentN_taskM_*.m script per investigation task
    docs/                    - Spandan_Final_Pipeline_Report.md (clean adopted-pipeline report), DATA_FORMAT.md,
                                SpO2_Final_Report_Section.md, and one Segment*_Task_*.md per investigation (the
                                detailed derivation/evidence layer — see §11 for the index)
    tests/                   - sanity_test.m, segment7_task_f_regression_test.m (3-part regression check, still passing)
  data/                       <- git-ignored, not in a fresh clone
    raw/UBFC-rPPG/DATASET_1/, DATASET_2/
    raw/VIPL-HR/               <- working extracted subset the pipeline reads (see §9)
    raw/PURE/                  <- empty, reserved (access request pending)
    processed/                 <- cached .mat intermediates (generated)
    self_collected/            <- reserved, not yet populated
  results/                    <- git-ignored: figures/, metrics/, logs/ (all generated)
  docs/                        <- cross-cutting docs: DATA_FORMAT.md, VIPL/Hoffman data-format notes, Android HR-switching port spec
  android/                     <- Kotlin/CameraX/ML Kit app, fully implemented, defense-ready
    README.md                  <- full port history + verification results
    docs/                       <- Defense_Readiness_Checklist.md, Segment*_Task_*.md (Android-side investigations)
    app/                        <- Gradle Android project
  ios/                          <- Swift/UIKit/AVFoundation/Vision port. Algorithm core CI-unit-tested; camera
                                    pipeline NOT verified on physical hardware — see ios/README.md's "Known risk areas"
```

---

## 6. Toolchain & environment

- **MATLAB R2024b** — primary implementation environment. `cd` into
  `matlab/`, run `startup.m` to add all `src/` subfolders to the path,
  then see `docs/DATA_FORMAT.md` before running anything under `scripts/`.
- **Android**: Kotlin, CameraX, ML Kit (Gradle project under `android/`).
  Build with `./gradlew assembleDebug`. All real-device testing in this
  project so far has been on a single Samsung Galaxy A35 — any similar
  Android 7.0+ phone should work, but only that model has actually been
  verified. To try the app without building it: grab the latest debug APK
  from the GitHub Releases page and sideload it (allow "install from unknown
  sources", install, grant camera permission on first launch).
- **iOS**: Swift/UIKit/AVFoundation/Vision, CI-built via
  `.github/workflows/ios-build.yml` on a macOS runner (built without a Mac or
  physical iPhone on hand). Requires iOS 16+, a physical iPhone (Simulator
  has no camera). Unsigned build — grab `Spandan-ios-unsigned.ipa` from the
  Releases page and sideload with a free tool (e.g. Sideloadly) using your
  own free Apple ID; free Apple IDs re-sign apps for 7 days at a time, so it
  needs reinstalling weekly.
- **Document generation** (for reports/proposals, separate from the MATLAB
  pipeline itself): Node.js + docx-js (Word), pandoc + xelatex (PDF pipeline,
  wide tables need raw LaTeX `\resizebox`, tcolorbox divs need a Lua filter
  `div_envs.lua`), pdflatex standalone class for equation PNGs (accepted
  fallback when native OOXML math rendering fails), python-docx + LibreOffice
  for inspection/conversion.
- **MATLAB code style** (Abrar's own use, for anything he needs to defend
  live): beginner-authentic — explicit for-loops, `disp`/`num2str` (not
  `fprintf`), no anonymous functions or clever compression, no inline
  comments, one statement per line. (Teaching-PDF MATLAB snippets may be
  heavily commented, since those are instructional, not code he owns.)
- **Project proposals**: prospective voice ("we will…"), never completed-work
  phrasing; no comparison language referencing other groups.

---

## 7. Current production defaults (if you read nothing else, read this)

| Setting | Default | Where |
|---|---|---|
| Wavelet denoising | **ON** (`useWaveletDenoise=true`) | MATLAB batch scripts; `WaveletDenoise.kt` on Android |
| Branch 2 confidence gate | **ON** (`opts.useConfidenceGate=true`) | `pipeline/estimateVitalsAndMorphology.m` — set `false` for pre-2026-09-13 pure-ABPF behavior |
| Bandpass mode (Branch 2) | **`wide`** (0.5–8 Hz) | `bandpassMorphology.m`'s `bandMode` arg — `mid` (0.6–6 Hz) validated as a low-risk non-default alternative, not switched |
| cPACE Stage 1 (isochromatic-pulsation projection) | **OFF** | `pulseextraction/cpaceProjection.m` — proven exact no-op for POS, modest regression for CHROM; available as an explicit opt-in flag only |
| cPACE Stages 2–3 (eigenvector + homodyne) | **OFF** | `cpaceEigenExtract.m` / `cpaceHomodyneNormalize.m` — full pipeline regresses HR MAE vs. production at every tested setting |
| RAKF/Kalman HR smoothing | **Rejected**, not available as a toggle | Worst of 6 methods tested on real data, both MATLAB (`residualAdaptiveKalmanHR.m`) and Android (explicitly not revisited in Segment 16) |
| Android HR display smoothing | **ON** (`ENABLE_HR_DISPLAY_SMOOTHING_DEFAULT=true`) | `DisplaySmoother.kt` — display-layer-only rolling median (window=5), does NOT feed back into the pipeline; cut tick-to-tick jitter 17.46→5.49 bpm on real device A/B |
| Android SpO2 perfusion-index exposure | **ON**, informational only | `LiveSpo2Estimator.kt` — `lastPerfusionIndexRed/Blue`, zero effect on the calibration formula |
| Multi-region (cheek) ROI | **OFF**, experimental only | `MultiRegionProfilingFaceAnalyzer.kt` (Android, debug-only, never live-wired); MATLAB multi-region code exists in `roi/extractROISignals.m` but single-forehead-ROI stays the shipped decision |
| `run_spandan_interactive.m` | Single MATLAB file, self-locates `matlab/src/` via `addpath(genpath(...))` and calls the real current pipeline — **can no longer be copied alone to a machine with no repo checkout** (needs `matlab/src/` next to `matlab/scripts/`) | Rewritten Segment 17 — **not yet re-run in MATLAB to confirm** (no MATLAB available in the session that did the rewrite) |

---

## 8. Validated results (headline numbers)

**Branch 1, pooled 112 subjects (5 UBFC-D1 + 107 VIPL), current defaults
(with wavelet denoising)**:

| Combiner | MAE (bpm) | RMSE (bpm) | Pearson r |
|---|---|---|---|
| CHROM | 7.83 | 11.87 | 0.53 |
| POS | **7.22** | **10.85** | **0.62** |

(Pre-wavelet-denoising numbers, preserved not deleted:
CHROM 9.10/18.00/0.31, POS 8.68/16.45/0.28.)

- **Plain POS beats CHROM/POS switching** on the pooled dataset once a v7
  scenario is included — the switching advantage depended on a
  CHROM-wins asymmetry that disappears with v7.
- **Device effect confirmed**: webcam (~10 bpm MAE) vs. phone (~16 bpm MAE)
  — a device effect, not a motion effect.
- **Best ROI shifts by scenario**: cheek wins baseline/dark, forehead wins
  motion/bright — but multi-region findings were deliberately **not** ported
  to the app; single forehead ROI is the standing, evidence-based decision.
- 7/112 subjects regress by >10 bpm on CHROM even as the pool improves under
  wavelet denoising (worst: VIPL p85, 0.44→45.81 bpm) — an honest, on-record
  caveat, not swept under the rug.

**Branch 2 (waveform morphology / notch), current production
(confidence gate)**: pass rate (subjects clearing the 0.3 notch-confidence
bar) **24% → 47%** on the 100-subject audit pool and **45% → 58%** on the
33-subject held-out UBFC-D2 set, **zero severe regressions by construction**
across all 133 subjects tested — the strongest single validated result in
the whole Segment 10–17 investigation line.

**SpO2**: calibration finalized (A=96.4763, B=−0.41595) but **honestly
reported as weak** — stratified LOSO MAE 1.908 (VIPL), does not beat a
trivial "guess the training mean" baseline within the narrow observed SpO2
range. Root cause: insufficient physiological SpO2 variance in healthy
subjects + a cross-camera Simpson's-paradox offset — a data limitation, not
a code bug. Live and working on Android (confirmed 2026-09-14: 96.81% SpO2
alongside 130 bpm HR on real hardware, zero crashes).

**Android throughput**: 13.44 fps → 21.40 fps steady-state (~1.6×) after an
every-Nth-frame ML Kit detection-skip optimization, measured on real
hardware, short of a naive 3× projection because detection isn't the app's
only per-frame cost.

---

## 9. Datasets — what you need and where to get it

Because `data/` is git-ignored, **a fresh clone has none of this**. To get a
working environment on a new machine:

- **UBFC-rPPG DATASET_1** (5 subjects, used throughout, has both HR and SpO2
  ground truth) and **DATASET_2** (42 subjects, 9 of which have a
  duplicate-timestamp data-quality issue in their own `ground_truth.txt` — 33
  usable — used for Segment 14's held-out validation): publicly downloadable
  from the UBFC-rPPG dataset's own distribution page. See
  `docs/DATA_FORMAT.md` in the repo for exactly what to extract from the
  (somewhat messy) source download and where it needs to land under
  `data/raw/UBFC-rPPG/`.
- **VIPL-HR** (Dr. Hu Han / Yunchi Zhang, ICT CAS) — requires requesting
  access from the maintainers (contacts in §16); not a public download. Once
  obtained, extract into `data/raw/VIPL-HR/` per `docs/DATA_FORMAT.md`.
- **PURE** — reserved, empty in this project, access request pending; not
  currently used.
- **Self-collected Bangladeshi test set** (pipeline stage 7) — **not
  started**. A flagged prediction on record for when it happens: because
  leakage from the isochromatic-pulsation problem (see §10) grows with
  skin-colour angle (~5–10° light skin, 30–50° dark skin in the literature's
  cohorts), this set is predicted to sit at a **higher** angle than UBFC/VIPL
  and perform **worse** under the current pipeline — worth recording before
  collecting data, not after.

If you're picking up this project from Abrar directly rather than starting
completely cold, ask him for the already-extracted dataset folders rather
than re-downloading/re-requesting everything from scratch — he has a working
copy set up.

---

## 10. Standing findings & decisions (the things that don't change session to session)

- **Isochromatic pulsation (the core mechanistic finding of this whole
  project's Segment 10 investigation line)**: Kaur, Lakshminarayanan & Saini
  (*Biomed. Opt. Express* 17(7):3832, 2026) argue the standard rPPG model
  (chromatic-only, what CHROM/POS assume) is incomplete — a second
  cardiac-frequency component, "isochromatic pulsation" (ballistocardiographic
  skin-geometry modulation), lies along the skin's mean reflectance direction
  q̂, carries the *majority* of cardiac-band energy (median 69–83% across
  their cohorts), and **cannot be separated by temporal filtering** since it
  shares the same frequency as the real cardiac signal. This mechanistically
  explains this project's own measured phase distortion, missing 2nd-harmonic
  energy, and independently predicts POS > CHROM (POS's basis is orthogonal
  to [1,1,1] by construction; CHROM's is not, so it leaks even at zero
  skin-colour angle). Their fix, cPACE, was fully implemented (Stages 1–3,
  Segments 11 & 15) and evaluated honestly — it does **not** beat production
  POS/CHROM on this project's own light-skinned, low-motion cohort, so it
  stays an off-by-default option, not a rejection of the underlying science.
- **Waveform fidelity is genuinely modest** even after all this work: median
  ground-truth waveform correlation sits at r=0.44–0.52. This is now
  understood mechanistically (isochromatic contamination), not treated as a
  simple bug to be patched away.
- **`notchDetectIEM.m`'s raw boolean output is a useless gate at pool scale**
  (100/100 subjects register "detected" with the default 0.3 confidence bar
  being the metric that actually carries information; only ~26–28% of a
  VIPL-dominated pool clears it).
- **The confidence-gated Branch 2 filter
  (`harmonicFilterConfidenceGate.m`) is this project's single best-supported
  result** — validated with zero severe regressions across 133 subjects on
  two independently-composed pools, and the only change in the entire
  Segment 11–14 investigation line to reach production.
- **Evaluation-honesty principles this project holds itself to** (apply to
  any future work here or elsewhere): small-sample accuracy inflation is a
  real, seen risk (Spandan HR: r=0.824 at N=18 → r=0.314 at N=112); same-subject
  train/test splits inflate accuracy; real datasets beat synthetic ones;
  data limitations get documented, not hidden (the SpO2 weakness is reported
  plainly); cross-camera/cross-session confounds (Simpson's paradox) must be
  controlled for; every external citation carries an explicit
  VERIFIED-FULL / VERIFIED-INDEX / BLOCKED marker — never cited as confirmed
  without one.
- **A pooled-metrics-only view can hide catastrophic per-subject failures** —
  seen twice independently (Segment 12's 17-subject Gaussian-filter
  regression that a pooled median completely hid; Segment 15's two UBFC-D1
  subjects swinging ~40 bpm at one cPACE bandwidth setting, invisible in the
  pooled number). Always check per-subject, not just pooled, before adopting
  anything.

---

## 11. Segment-by-segment history (condensed index)

Each entry is a one-line pointer; full derivation lives in the named
`docs/Segment*_Task_*.md` file inside the repo.

- **Segments 1–6**: Core pipeline built and LOSO-validated (face
  detection → ROI → filter → CHROM/POS → FFT; SpO2 ratio-of-ratios +
  calibration). Segment 6 explored device-stratified eval, multi-region ROI,
  detrend/bandpass tuning, windowed harmonic continuity, phone-camera SpO2
  centering (Tasks L/N/O/P/Q/R) — some adopted (phone SpO2 needs no
  device-specific centering), most not ported to Android this close to
  defense.
- **Segment 7**: `pipeline/estimateVitalsAndMorphology.m` built as the real
  orchestrator (Task F); ROI experiments — baseline box vs. KLT vs. real
  face-mesh polygon vs. hybrid (Tasks H/I/J) — **no variant beats the simple
  axis-aligned box** on the notch metric; template-collapse diagnostic
  (Task K) found **no support** for collapse; phase-distortion assessment
  (Android, Task H) confirmed `filtfilt` zero-phase filtering is already
  correct by construction.
- **Segment 8**: VIPL source2 (phone) FPS mismatch root-caused and fixed via
  relabeling (Task 3, real cubic-spline correction tested and rejected — no
  real per-frame timestamps to correct from); **DWT wavelet-shrinkage
  denoising** (Task 4) — genuine pooled improvement, later promoted to
  default; **RAKF/Kalman smoothing** (Task 5) — tested, rejected, worst of 6
  methods; Android frame-skip throughput optimization measured for real
  (13.44→21.40 fps).
- **Segment 9 ("Field Guide" pilots, all small-sample, none adopted)**:
  Android multi-region ROI feasibility (promising, negligible fps cost, not
  scaled up); RAKF parameter sweep (doesn't rescue RAKF); a weighted
  region-switching rule (ambiguous, small real wins in one scenario only).
- **Segment 10**: Full rPPG-vs-ground-truth waveform fidelity audit
  (100 subjects, 6 headline findings); a literature search that surfaced the
  isochromatic-pulsation paper as the project's central mechanistic finding;
  4 Tier-0 diagnostics (3 supported, 1 — the camera-frame-rate "ceiling"
  explanation — **not** supported and ruled out).
- **Segment 11**: cPACE Stage 1 implemented — proven exact no-op for POS,
  modest regression for CHROM, kept off-by-default; cross-ROI PLV promoted
  to a standing validation metric.
- **Segment 12**: `bandpassMorphology.m`'s `mid` mode evaluated (small,
  non-regressive win, not adopted as default); Harmonic-Selective Gaussian
  Filtering implemented and evaluated (underperforms ABPF at the paper's own
  parameter; a tuned parameter beats it but with a 17-subject regression
  cost — not adopted).
- **Segment 13**: Root-caused the Gaussian filter's 17-subject regression
  (all were subjects ABPF already passed — a confidence-metric ceiling-clip
  artifact); built `harmonicFilterConfidenceGate.m`, which beats both
  ingredients on every metric with zero severe regressions.
- **Segment 14**: Held-out validation of the confidence gate on UBFC-D2
  (33 valid subjects) replicated the zero-severe-regression guarantee
  exactly; **promoted to production default**
  (`opts.useConfidenceGate=true`). Confirmed Branch 2 was never on Android,
  so no Android change needed.
- **Segment 15**: Full cPACE Stages 2–3 (eigenvector selection + homodyne
  normalization) built from the actual paper (main text + Supplement),
  correcting an earlier wrong claim that no second eigenvector candidate
  exists; implemented dominant-eigenvector-only (documented deviation); a
  real Hilbert-transform-precondition bug found and fixed via testing; final
  honest result: the full pipeline does **not** beat production POS/CHROM at
  any tested setting — kept off-by-default.
- **Segment 16 (first Android-focused segment)**: HR display-level
  smoothing (`DisplaySmoother.kt`, real on-device A/B: jitter −69%,
  promoted to default; two real bugs found and fixed via the same test);
  SpO2 confirmed genuinely live via fresh on-device check + literature
  search (no adoptable calibration replacement found, none forced);
  presentation-only UI/UX redesign (vitals card, status pills, no-face
  banner) verified on real hardware, one real bug found and fixed.
- **Segment 17**: `scripts/run_spandan_interactive.m` — the standalone demo
  script — rewired from a frozen, silently-stale Segment-7/8 pipeline
  snapshot to call the actual current `matlab/src/` pipeline via
  `addpath(genpath(...))`. Abrar explicitly rejected a first attempt that
  did this by deleting the file's local function copies and just adding the
  addpath bootstrap with nothing else changed — he wanted **all** the
  pipeline functions re-copied verbatim into one self-contained file, no
  `matlab/src/` dependency at all. That version was rejected as
  unmaintainable (it's exactly what went stale before); the version actually
  shipped uses `addpath` and is flagged as **not yet re-run in MATLAB** to
  confirm correctness — do that before a live demo.

---

## 12. Do-not-touch list (validated, regression risk only)

`pulseextraction/chromCombine.m`, `pulseextraction/posCombine.m`,
`heartrate/fftHeartRate.m`, `morphology/adaptiveHarmonicFilter.m`'s existing
behavior, `filtering/waveletDenoise.m`'s internals (now a production
default — only its call sites should change), `morphology/
harmonicFilterConfidenceGate.m`'s own gating logic (0.3-bar/ABPF-primary/
Gaussian-0.15-fallback design is settled and validated on 133 subjects —
re-tune only with a new, explicit ablation), `android/.../signal/
WaveletDenoise.kt`'s internals, `FaceAnalyzer.kt`'s frame-skip logic
(measured and adopted), `BandpassFilter.kt`'s `filtfilt` implementation
(confirmed zero-phase/correct), anything marked done in `android/docs/
Defense_Readiness_Checklist.md` — except where a specific task explicitly
adds an alternative alongside it.

---

## 13. Flagged follow-ups not yet done (real, on-record, not started)

- Port `chooseHeuristicPolarityByNotchConfidence` (the old interactive
  script's confidence-anchored polarity-selection logic for no-ground-truth
  clips) into `morphology/fixPolarity.m` itself, or add it as an
  `opts.polarityMethod` hook on `estimateVitalsAndMorphology.m` — currently
  Cases 2/3 fall back to the plain skewness heuristic, which has a
  documented bias (flips all 5 UBFC subjects when only 3 needed it).
- Re-run `scripts/run_spandan_interactive.m` once inside real MATLAB to
  confirm the Segment 17 rewrite actually works end-to-end (only
  structurally verified so far, not executed).
- Investigate the Harmonic-Selective Gaussian Filter's regression-tail
  subjects further, try adaptive/per-subject alpha, or combine a tighter
  alpha with more harmonics — flagged as the most promising open lead in the
  whole Segment 10–13 investigation line, not pursued past Segment 13's gate
  fix.
- A dedicated multi-minute SpO2 stability re-run on Android (the original
  4.5-minute run stands from earlier work, not repeated in Segment 16).
- Spacing/sizing verification of the Segment 16 UI redesign on a screen
  density other than the one test device; whether the 1200ms no-face-banner
  debounce timing feels right beyond one session's interaction.
- The self-collected Bangladeshi test set (pipeline stage 7) — not started;
  remember the skin-colour-angle prediction in §9 before collecting.
- Consider scaling up any of the three Segment 9 "Field Guide" pilots
  (multi-region ROI on Android — promising; RAKF sweep — no; weighted region
  switching — ambiguous) if a future session decides it's worth it. None are
  automatic next steps.

---

## 14. Working preferences (how Abrar wants this project run)

- Casual, direct communication; prefers clean, complete, **submission-ready**
  deliverables over outlines or drafts.
- Prefers direct execution over confirmation gates — skip "wait for
  go-ahead" steps unless genuinely necessary; comfortable skipping
  intermediate diagnostic steps when confident.
- **Code-ownership awareness is an explicit, standing concern**: he has
  received Claude-built code he couldn't fully defend live. Manage this
  through active onboarding/explanation as code is built, not just delivery
  — especially relevant given he must defend this project live to a
  supervisor.
- When teaching any DSP concept (however small) related to this project: act
  as an outstanding EEE 312 professor — gauge his current understanding
  first, teach at his level, check the explanation is landing before moving
  on; intuition/analogies before formulas, concrete before abstract, one
  idea per check.
- Update the relevant project docs (`SESSION_HANDOFF.md` first and
  foremost) **immediately** as part of finishing any session that changes
  project state — not as an afterthought. This is a standing, explicitly
  stated rule, not just a nice-to-have.
- Uses Claude Code as a separate agentic coding tool for this project day to
  day; wants **paste-ready prompts** for it, not prose descriptions of
  fixes, when work needs to be handed off there.
- Freely propose fresh project-idea directions when relevant, not
  necessarily tied to any one existing pipeline; separately note whether/how
  an idea could reuse Spandan's existing MATLAB architecture.
- Values a teaching/presentation style that leans on real images/photos with
  captions rather than text alone, generally (not project-specific).

---

## 15. How to resume on a brand-new device (concrete steps)

1. **Get the repo**: clone `spandan` from GitHub
   (`Thunder-Bird-007/spandan_contactless_vital_sign`, branch `main`) — or,
   if you're picking this up directly from Abrar or another collaborator,
   copy their working folder.
2. **Read** `SESSION_HANDOFF.md` in the repo root — it is the authoritative,
   most-current status (more current than this document by definition, since
   it's updated every session).
3. **MATLAB side**: install MATLAB R2024b (or compatible), `cd` into
   `matlab/`, run `startup.m`. Datasets are git-ignored — see §9 for how to
   get UBFC-rPPG (public download) and VIPL-HR (request access from the
   maintainers) and where to extract them.
4. **Android side**: open `android/` in Android Studio (or
   `./gradlew assembleDebug` from the command line). Testing so far has all
   been on one physical Android phone (a Galaxy A35) — real hardware is
   preferable to an emulator, since at least one emulator setup previously
   failed to finish booting in 20+ minutes.
5. **iOS side**: only relevant if extending/testing the iOS port — see
   `ios/README.md`'s "Known risk areas" before trusting it; no physical
   iPhone has verified the camera pipeline yet.
6. **Before changing any pipeline code**: check §12's do-not-touch list and
   `SESSION_HANDOFF.md`'s own (more current) copy of it.
7. **After finishing any work**: update `SESSION_HANDOFF.md`'s Current
   State / Active Work Queue / Changelog per its own Maintenance Protocol
   (strike through superseded lines rather than deleting them, date every
   entry, name the actual output files produced) — this is a hard project
   convention, not optional housekeeping.

---

## 16. Contacts

| Who | Role |
|---|---|
| Prof. Dr. Md. Kamrul Hasan | EEE 312 supervisor |
| Ramis Isfar | Spandan group collaborator |
| Bayezid Rahman | Spandan group collaborator |
| Lubaba Tasnia Khan | Spandan group collaborator |
| Dr. Hu Han (hanhu@ict.ac.cn) | VIPL-HR dataset maintainer |
| Yunchi Zhang (zhangyunchi19@mails.ucas.ac.cn) | VIPL-HR download logistics (grad student/RA) |

---

*End of master handoff. For anything not covered here, the repo's own
`SESSION_HANDOFF.md` and the per-segment `docs/Segment*_Task_*.md` files are
the ground truth — this document summarizes and points to them, it does not
supersede them.*

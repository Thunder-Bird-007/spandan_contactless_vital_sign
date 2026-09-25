# Spandan — Session Handoff & Active Work Queue

> **READ THIS FILE FIRST, before README.md, before any Segment*/Task_* doc, before
> touching any code.** This is the living entry point for any Claude session (fresh
> CLI session or otherwise) opening this repo. It exists so that a session with zero
> memory of prior conversations doesn't redo finished work, doesn't build on top of a
> broken/incomplete result, and doesn't lose track of what's actually in flight.
>
> For the *finished, adopted* pipeline (what ships, what's validated), read
> `docs/Spandan_Final_Pipeline_Report.md` next. For deep history of any one task, the
> individual `docs/Segment*_Task_*.md` files are the record. This file is neither of
> those — it's the current-status-and-todo layer that sits on top of both.

---

## MAINTENANCE PROTOCOL — read this before you edit this file

This file only stays useful if every session that changes project state updates it
before finishing. Follow these rules, the same discipline the rest of this project
already uses (see README.md's own "mark superseded, don't delete" convention):

1. **Update "Current State" and "Active Work Queue" below whenever you**: complete an
   action, discover a new bug/finding, start something not already listed, or change
   the status of something already listed. Do this as part of finishing the session,
   not as an afterthought.
2. **Never silently delete a status line.** If something is superseded, wrong, or
   fixed, strike it through (`~~like this~~`) and add the corrected line next to it,
   the same way `README.md`'s "Current status" section and
   `android/docs/Defense_Readiness_Checklist.md`'s update notes already do. History
   stays visible.
3. **Always append to the Changelog section at the bottom** — one dated entry per
   session that touches this repo, one or two lines, pointing at the actual doc/CSV
   with the details rather than duplicating them here. Never edit a past changelog
   entry except to fix a factual error in it (and say so inline).
4. **Date every status update** (`YYYY-MM-DD`, the date of the session, not the date
   this template was written). If you don't know today's date, ask rather than
   guessing or omitting it.
5. **When you check off or update an Active Work Queue item, name the actual output
   file(s) it produced** so the next session can verify rather than re-run.
6. **If you find this file itself is stale or wrong when you start a session**, fix it
   as your first action, using rule 2 above — don't work around a stale file silently.

---

## Current State

*(Last updated: 2026-09-20. If you are reading this later and nothing below has been
touched since, treat it with suspicion — either nothing happened, or someone skipped
step 1 of the protocol above.)*

- **Architecture**: two branches off one shared ROI extraction (`roi/extractROISignals.m`).
  Branch 1 = production HR/SpO2, narrow 0.7-4Hz band. Branch 2 = waveform morphology /
  dicrotic notch, wide 0.5-8Hz band + harmonic-comb filter
  (`morphology/adaptiveHarmonicFilter.m`). **These are deliberately not merged** — the
  wide-band/harmonic-comb filtering that Branch 2 needs measurably breaks Branch 1's HR
  accuracy (harmonic-lock: one VIPL subject's CHROM jumped 69.4→140.8bpm under it). Full
  detail: `docs/Spandan_Final_Pipeline_Report.md`.
- **Branch 1 validated result**: ~~pooled 112 subjects (5 UBFC + 107 VIPL), CHROM MAE
  9.10bpm/r=0.31, POS MAE 8.68bpm/r=0.28~~ **[2026-09-13] PROMOTED TO DEFAULT**: DWT
  wavelet-shrinkage denoising (`filtering/waveletDenoise.m`, Segment 8 Action 4) is now
  the default pre-step in both MATLAB (`useWaveletDenoise` toggle, default `true`, in
  `scripts/run_segment3_filtering_batch.m` / `run_vipl_integration_batch.m`) and Android
  (`WaveletDenoise.kt`, wired into `RealHeartRateEstimator.kt`). New pooled 112-subject
  result: CHROM MAE **7.83bpm/r=0.53**, POS MAE **7.22bpm/r=0.62**
  (`results/metrics/segment6_hr_pooled_metrics.csv`, verified to match
  `docs/Segment8_Task4_Wavelet_Denoise_Ablation.md`'s own pooled table exactly). Pre-wavelet
  numbers preserved, not deleted, in
  `results/metrics/segment6_hr_pooled_metrics_prewavelet.csv`. Known caveat still on the
  record: 7/112 subjects regress by >10bpm on CHROM even as the pool improves (worst:
  VIPL p85, 0.44→45.81bpm) — see Action 4's own entry below and the ablation doc.
- **Branch 2 validated result**: `adaptiveHarmonicFilter.m` (a direct port of Moço,
  Stuijk & de Haan's ABPF, *Sci Rep* 8:8501, 2018 — verified real, not a hallucinated
  citation) gets 4/5 UBFC subjects above the 0.3 notch-confidence bar, vs. 1/5 for the
  flat-band baseline. This is this project's current best-supported single intervention
  for the notch. Small-N (5 subjects) caveat applies, same as everywhere else in this
  project. **[2026-09-13] Still the production choice after two head-to-head challenges
  on the full 100-subject pool**: `morphology/harmonicSelectiveGaussianFilter.m` (NEW,
  gated, Segment 12 Task 2) underperforms it at the source paper's own parameter and
  only beats it at a tuned parameter with a real 17-subject regression cost, not
  adopted; `bandpassMorphology.m`'s existing `'mid'` mode as the shared-f0 input
  (Segment 12 Task 1) gives a small strictly-non-regressive win untargeted at the
  hypothesis that motivated testing it, also not adopted as the new default. See
  the Active Work Queue entries below for both. **[2026-09-13, Segment 13]** The
  Gaussian filter's own 17-subject regression (at its best tested parameter,
  alpha=0.15) has a clean root cause: every regressor was a subject ABPF already
  passed (17/24 ABPF-pass subjects regress severely vs. 0/76 ABPF-fail subjects) —
  four other hypotheses (dataset, device/source, HR range, skin-colour angle) were
  checked and ruled out/inapplicable. A well-supported gated fix followed:
  `morphology/harmonicFilterConfidenceGate.m` (new — keep ABPF wherever it already
  passes, substitute Gaussian(0.15) only where ABPF fails) beats BOTH ingredients
  on every metric at once — pass rate 24%(ABPF)/31%(Gaussian alone)/**47% (gated)**,
  median waveform corr 0.519/0.523/**0.522**, harmonic confusion 5%/3%/**3%**, and
  **zero severe regressions by construction**. A supplementary multi-candidate
  variant (pick whichever of several alphas self-reports highest confidence) was
  tested and explicitly rejected — 64% pass rate but median corr (0.508) the WORST
  of any method, a demonstrated selection-bias artifact, not a real gain. **This
  gated fix is this project's best-supported single Branch 2 result to date** —
  ~~still NOT adopted into production (stays a gated, off-by-default utility, per
  the task's own instruction)~~ **[2026-09-13, Segment 14] PROMOTED TO PRODUCTION
  DEFAULT** after a genuinely held-out validation (UBFC DATASET_2, 42 subjects,
  never touched by any prior segment) replicated the gate's own defining property
  — zero severe regressions — across 133 total subjects (100-subject audit pool +
  33 valid held-out subjects), with pass rate improving on both (24%→47% audit
  pool, 45%→58% held-out). `pipeline/estimateVitalsAndMorphology.m`'s
  `opts.useConfidenceGate` now defaults to `true`; the one honest caveat is that
  this makes NO difference on the tiny 5-subject legacy UBFC-D1 benchmark (still
  4/5 pass, since only 1 of 5 subjects is even eligible for substitution, and it
  isn't rescued) — stated plainly, not smoothed over. Android unaffected (Branch 2
  was never ported there, confirmed from existing docs, not guessed). See the
  Segment 13 and Segment 14 Active Work Queue entries and
  `matlab/docs/Segment13_Task1_Gaussian_Regression_Root_Cause_and_Gate.md`,
  `matlab/docs/Segment14_Task1_UBFC_D2_Held_Out_Validation.md`,
  `matlab/docs/Segment14_Task2_Confidence_Gate_Production_Promotion.md`.
- ~~**⚠️ BROKEN, not yet usable**: Segment 7 Task J ran but produced empty output.~~
  **[2026-09-12] FIXED AND COMPLETE.** Root cause was a per-landmark MATLAB↔Python
  round-trip leak (468 landmarks × 2 attribute reads/frame as separate calls leaked
  proxy handles, crashing MATLAB with a stack overflow partway through subject 2) —
  fixed by batching each frame's landmark extraction into one Python-side list
  comprehension. Both batches then ran clean, 0 failures. **Result: partial
  confirmation, still net-negative.** Giving the face-mesh detector baseline's
  pixel-pooling box (instead of the thin 4-landmark polygon) recovers notch confidence
  on 1/5 subjects (up from face-mesh's 0/5) — pixel count is a real factor — but it's
  nowhere near baseline's 4/5 and is *below* Task D's KLT proxy (2/5). Ranked: Baseline
  (4/5) > KLT (2/5) > Hybrid (1/5) > Real face-mesh polygon (0/5). **No ROI variant
  beats the simple axis-aligned box on the notch metric.** HR parity confirmed again:
  Branch 1 CHROM/POS bit-for-bit identical to baseline on all 5 subjects (verified
  directly against `results/metrics/segment7_task_j_facemesh_hybrid_branch1_hr.csv` —
  matches). Full writeup: `docs/Segment7_Task_J_FaceMesh_Hybrid_ROI.md`. **Gotcha worth
  remembering for any future MATLAB↔Python (py.*) work in this repo**: never loop
  per-element attribute reads across a py.* boundary one at a time — batch into a single
  list comprehension on the Python side per call, or risk a proxy-handle leak/stack
  overflow on anything with enough elements (468 landmarks was enough to crash it).
- **Segment 8 source2 FPS problem**: ~~Open, real, partially-investigated problem ...
  Not resolved. See Active Work Queue Action 3.~~ **[2026-09-13] CLOSED.** 12 VIPL
  source2 (phone) subjects have real container-vs-true FPS mismatches (ratio
  0.95x-2.08x, `results/metrics/segment8_source2_fps_investigation.csv`). **Adopted
  fix**: relabel with a corrected constant fps
  (`results/metrics/segment4_hr_summary_vipl_source2_fpsfix.csv`) — mean CHROM error
  across the 12 improves 19.4→13.8bpm, though 4 of 12 subjects (p84/p100/p104/p107)
  still regress under it, for reasons investigated but not conclusively explained (best
  guess: source2's own uncorrectable per-frame capture jitter). **Tested and rejected**:
  real cubic-spline timing correction (Chen/Lin/Jeong 2025) — source2 has no real
  per-frame timestamps to spline from, and the naive version tested doesn't beat the
  relabel fix (18.74bpm vs. 13.83bpm pooled MAE). See Archive Action 3 below for the
  full investigation.
- **Android app**: defense-ready per `android/docs/Defense_Readiness_Checklist.md` (all
  7 checklist actions done, 16.1min crash-free stability run). ~~Most recent work:
  `android/docs/Segment7_Task_G_Throughput_Profiling.md` measured real on-device
  throughput (~13.4fps steady-state, ML Kit detection = 98.5% of per-frame cost) and
  proposed but **did not implement** an every-Nth-frame detection-skip optimization.~~
  **[2026-09-13]** The every-Nth-frame detection-skip is now implemented AND
  re-measured for real: **13.44fps → 21.40fps steady-state** (~1.59x, below the naive
  3x projection — see Active Work Queue Action 6a, now closed). Separately, DWT
  wavelet-shrinkage denoising (`WaveletDenoise.kt`) is now also the default Branch 1
  HR pre-step on Android, matching the MATLAB promotion above — see Active Work Queue
  Action 7. **[2026-09-14, Segment 16]** HR display-level smoothing built
  (not RAKF/Kalman — see below), SpO2 calibration audited + a 2023+
  literature search done (no adoptable replacement found, none forced), and
  a UI/UX redesign shipped (vitals card, per-metric status pills, no-face
  banner). Started with no physical device (local emulator never finished
  booting, 20+ minutes, never past `offline`) but **a real device became
  available partway through and most of this IS on-device-verified**: a
  real A/B capture found smoothing cuts mean tick-to-tick HR jitter ~69%
  (now promoted to on-by-default), a real bug in that same capture's
  smoothing window was found and fixed, real before/after captures verified
  the UI redesign (including a real text-wrap bug found and fixed; no
  screenshot files retained — deleted at the user's request, never
  committed/pushed), and the SpO2 chip/logcat were freshly re-confirmed
  live. See the Segment 16 Active Work Queue entry for exactly what was and
  wasn't verified.
- **[2026-09-14, Segment 17] `scripts/run_spandan_interactive.m` rewired to call the
  CURRENT production pipeline, no longer a frozen snapshot.** This file was originally
  built (Segment 7/8) as a deliberately standalone, dependency-free single .m file —
  every pipeline function it used (`estimateVitalsAndMorphology`, `chromCombine`,
  `adaptiveHarmonicFilter`, `notchDetectIEM`, 16 others) was copied verbatim as a local
  function, by explicit design, so the file could be copied alone to a machine with no
  repo checkout. That design's own header warned this would "silently go stale" — and it
  did: Segments 10-16 (cPACE, the mid-band option, the harmonic-selective Gaussian
  filter, and Segment 14's confidence gate, now the actual production default) were
  never ported into those local copies, so this "single file that runs the pipeline"
  was quietly running a Segment-7/8-era pipeline snapshot with no on-screen indication.
  Abrar asked for a single file that runs the *current* pipeline and can pick any video
  on the machine. Fix: the ~1200 lines of duplicated pipeline functions were deleted;
  the file now self-locates `matlab/src/` (via `mfilename('fullpath')`, works from any
  MATLAB current folder) and `addpath(genpath(...))`s it at the top, then calls
  `pipeline/estimateVitalsAndMorphology.m` and every other function directly off the
  path — the same functions every batch/report script here already uses, so it can
  never silently go stale again. Cost, stated plainly: this file can no longer be
  copied alone to a machine with no repo checkout (needs `matlab/src/` next to
  `matlab/scripts/`, like every other script here). **One real piece of functionality
  this drops, flagged, not silently lost**: the old file's own
  `chooseHeuristicPolarityByNotchConfidence` (Cases 2/3, no ground truth) picked Branch
  2's waveform polarity by running both orientations through `notchDetectIEM` and
  keeping whichever scored higher confidence, instead of trusting
  `morphology/fixPolarity.m`'s plain skewness rule — written after a live demo review
  caught the skewness rule flipping a VIPL clip (p1/v1/source1) into an orientation
  with no real notch (confidence 0.04 flipped vs. 0.92 as-is). That fix was never
  ported into `matlab/src/`, so calling the real pipeline now means Cases 2/3 are back
  to the plain skewness heuristic — the same one production/Android already use for
  no-ground-truth input, arguably the more honest "current pipeline" answer, but the
  underlying skewness bias (also documented in `fixPolarity.m`'s own header: flipped
  all 5 UBFC subjects when only 3 of 5 needed it) is still unaddressed in `matlab/src/`.
  Flagged as a real follow-up if it still matters: port a confidence-anchored polarity
  choice into `morphology/fixPolarity.m` itself (or a new `opts.polarityMethod` hook
  on `estimateVitalsAndMorphology.m`) as a proper validated segment — not done here.
  The summary panel now also surfaces which Branch 2 filter the confidence gate
  actually used per clip (ABPF vs. Gaussian(0.15)), since that gate is production
  default now. Not run inside MATLAB from this session (no MATLAB available in the
  environment that made this edit) — structurally verified (every `function`/`if`/
  `for`/`while`/`switch`/`try` block balances against a standalone `end`, all removed-
  function call sites confirmed to match `matlab/src/`'s real signatures
  argument-for-argument) but **should be run once by Abrar to confirm** before relying
  on it for a live demo.
- **[2026-09-15/16, Segments 18-19] Android: camera throughput/tracking revisit, and
  Branch 2 (waveform morphology/dicrotic notch) ported to Android for the first time.**
  Real on-device verification, same Galaxy A35. **Segment 18**: a new gated
  (`useMotionTracking`, default `false`, so behavior is unchanged) optical-flow-style
  face-box tracker was built as an alternative to freezing the box between the existing
  N=3 detection-skip's real detections — measured cost negligible (<1ms/frame) but a real
  end-to-end throughput regression (~19-20fps → 16.33fps) was found and could NOT be fully
  attributed to thermal/session drift (a controlling re-check ruled that out) — **NOT
  adopted, stays off by default**, root cause flagged as an open question (likely
  per-frame allocation/GC pressure, unverified — no profiling tooling available this
  session). `SignalBuffer.WINDOW_DURATION_SECONDS` stays 25.0s (no new evidence to
  revisit it). **Segment 19**: Branch 2 (~~"never ported to Android," true as of every
  prior session~~ **no longer true**) is now a real, on-device-verified port —
  `MorphologyWaveformEstimator.kt` and 9 supporting files, a new "WAVEFORM MORPHOLOGY
  (BRANCH 2)" UI card, 49/49 unit tests passing, and a real ~40s on-device capture with
  zero crashes that exercised BOTH the WIDE/MID band fallback and the ABPF/Gaussian
  confidence-gate substitution on real data, confirmed Branch 1 unaffected. See the
  Segment 18/19 Active Work Queue entries above and their own dedicated docs
  (`android/docs/Segment18_Camera_Throughput_And_Buffer_Window.md`,
  `android/docs/Segment19_Branch2_Morphology_Port.md`) for the full numbers and caveats.
- **Data location note — read this before assuming "only 107 VIPL subjects exist"**:
  the working pipeline reads VIPL-HR from `spandan/data/raw/VIPL-HR/` (untouched,
  unchanged, no code path affected by anything below). The **original full VIPL-HR raw
  download (zip archives, 47GB, 30 files) lives on a different drive**:
  `I:\EEE 3-1\EEE 312\project\dataset\VIPL-HR-V1\` — moved there 2026-09-13 from
  `H:\EEE 312 project\Contactless Vital Sign\VIPL-HR-V1\` purely to free H: disk space
  (verified 0 failures, 30/30 files, 46.5GB; H: free space went 67GB → 114GB). **If a
  future task needs more/different VIPL subjects or scenarios than what's already
  extracted into `spandan/data/raw/VIPL-HR/`, check `I:\EEE 3-1\EEE 312\project` first**
  before assuming the dataset is exhausted or re-downloading anything — this is where
  the rest of it is. (A UBFC DATASET_2 extraction attempt before this move also briefly
  filled H: to 0 bytes and was rolled back cleanly, no data lost — see Archive Action 2's
  changelog entry for that story if relevant.)
- **External literature checked and verified real** (not hallucinated, actually read or
  confirmed via search): Moço/Stuijk/de Haan *Sci Rep* 8:8501 (2018, ABPF — integrated,
  Branch 2 default); Pal et al., *Comput Biol Med* 254:108283 (2024, PMC11323035, IEM
  notch detector — integrated); den Brinker et al., arXiv:2306.09879 (forehead PPG
  polarity — integrated); "Template Collapse..." arXiv:2606.03802 (2026,
  morphology-restoration limits — ~~NOT yet acted on~~ **diagnostic run 2026-09-13,
  passed, no retraction warranted**, see Archive Action 2); **that same paper's SECOND,
  separate claim (a ~30fps sampling floor for the dicrotic notch) tested 2026-09-13 via
  Segment 10 Task 3 Action 1 — NOT SUPPORTED, see Active Work Queue entry**; Kaur,
  Lakshminarayanan & Saini, *Biomed. Opt. Express* 17(7):3832 (2026, isochromatic
  cardiac pulsation — independently corroborated on Spandan's own data 2026-09-13 via
  Segment 10 Task 3 Actions 2 and 4; ~~not yet acted on as a fix~~ **their cPACE Stage 1
  fix implemented and evaluated 2026-09-13 (Segment 11 Task 1) — proven an exact
  algebraic no-op for POS and a modest empirical regression for CHROM on this project's
  own pool, NOT adopted, see Active Work Queue entry**; ~~Stages 2-3 not attempted~~
  **their cPACE Stages 2-3 (eigenvector extraction + homodyne normalization)
  implemented and evaluated 2026-09-14 (Segment 15) — the full Stage1+2+3 pipeline
  regresses HR MAE vs. production at every eigen-window bw value tested (best: 8.66bpm
  at bw=0.15 vs. production's 7.86-7.87bpm), with a small cross-ROI PLV gain; 42/100
  subjects regress >1bpm, 24/100 severely (>10bpm), NOT adopted, see Active Work Queue
  entry**); Debnath & Kim, *PLOS ONE*
  21(1):e0340097 (2026, DWT denoising — ~~NOT yet tried~~ **adopted as the Branch 1
  default**; residual-adaptive Kalman/RAKF from the same paper — **tested and
  rejected**, worst of 6 methods compared, see Archive Actions 4/5/7); Chen, Lin &
  Jeong, *Sensors* 25(2):588 (2025, low-complexity timing correction — ~~NOT yet
  tried~~ **tested for VIPL source2, does not beat the already-adopted relabel fix**,
  see Archive Action 3); Lapitan et al., *Sci Rep* 14:6546 (2024, IIR phase distortion
  in PPG filtering — ~~NOT yet checked~~ **checked against the Android app, confirmed
  inapplicable by construction**, see Archive Action 6b).
- **[2026-09-20, Segment 18 MATLAB colour-space + Segment 21 literature search]
  Motion-robustness investigation opened, not yet resolved.** Segment 18 tested CIELab
  a\*/YCbCr Cb/Cr as single-channel HR sources (5 UBFC + 107 VIPL v1, N=112, plus a new
  20-subject VIPL v2 large-head-motion pool never tested before). Result: a\* beats green
  (MAE 14.98→9.53bpm) but loses to production CHROM/POS (7.83/7.22bpm); under motion
  every single channel tested is poor (a\* best but r=0.11; green/Cb go *negative*,
  worse than chance) — **NOT promoted.** Full detail:
  `matlab/docs/Segment18_ColorSpace_Ablation.md`. That motion-collapse result opened
  Segment 21, a literature search for combiners specifically designed for motion
  robustness (this is Segment 10 Task 2's own Tier 2 item 14 — PBV/LGI/OMIT — finally
  read in full, plus 2SR and the VIPL-HR dataset paper's own motion-scenario context).
  **Ranked for Spandan**: LGI (strongest published head-rotation evidence, r=0.97 vs
  POS 0.56/2SR 0.51/ICA 0.16 in the source paper's own benchmark, but highest
  implementation cost) > 2SR (cheap, "a few lines of MATLAB," more modest motion gains)
  > PBV (needs camera spectral calibration, conflicts with this project's
  no-calibration design goal) > OMIT (validated for compression robustness, not
  motion — deprioritized for this specific problem). **Nothing implemented or run on
  Spandan's own data yet** — see the queued Segment 22 entry below. Full detail:
  `matlab/docs/Segment21_Motion_Robust_Combiner_Literature_Search.md`. A consolidated,
  project-wide index of every paper searched (this entry plus everything in Segment 10
  Task 2) is now maintained at `matlab/docs/Literature_Review_Master.md` — read that
  first for "what have we already looked at" before starting any new literature search.
  One blocked link recorded, not a dead end: the VIPL-HR paper's primary PDF host
  (`jdl.link`) has an expired server SSL certificate as of this date; the arXiv mirror
  (`ar5iv.labs.arxiv.org/html/1810.04927`) served the same content, so retry the direct
  link later rather than re-deriving the content.
- **[2026-09-20, Segment 22 — motion-robust combiner implementation + evaluation]
  Investigation closed: NO-GO for both 2SR and the LGI projection step.** Tier 0
  prerequisite run first: production CHROM/POS (wavelet default) had never actually
  been measured on the 20-subject VIPL v2 motion pool — it turns out to already be far
  better than Segment 18's single-channel numbers (MAE 8.85/10.57bpm, r 0.54/0.31 vs
  Segment 18's 14.5-21.8bpm), re-deriving Segment 8's exact 112-subject numbers
  (0.0000bpm diff) as a correctness check. Both new combiners then lost to that
  baseline everywhere it matters: 2SR MAE 21.3bpm on v2 motion (worse for 14-15/20
  subjects, 10-12 severe regressions >10bpm, p≈0.01) and 9.5bpm on the main pool (vs
  7.83/7.22); LGI projection-only (tracker not built — see rationale below) MAE
  16.9bpm on v2 motion (worse for 7-11/20, p≈0.02) and 9.2bpm on the main pool.
  Stratified by skin-angle/dataset/motion-level/frame-rate: neither ever clearly beats
  production in any stratum with a meaningful N; the closest, low-frame-rate v1
  (7.6bpm for 2SR vs 6.5-7.2bpm production), is still not a win. LGI's one bright spot
  (6.94bpm on the v1 rows of the same 20 subjects) is a single small stratum, not a
  confirmed result. ~~**LGI's state-space HR tracker was deliberately not built**~~ **[2026-09-20, Segment 23: built and evaluated, still NOT ADOPTED]** — the
  projection step alone is nearly equivalent to cPACE Stage 1 (Segments 11/15,
  evaluated and not adopted) and the closest existing tracker (`residualAdaptiveKalmanHR.m`)
  was already rejected in Segment 13, so per the staged-build plan, a losing projection
  step ends the line without paying for the tracker. Caveats disclosed in the doc: the
  final stride grid (including a 1-frame stride, 35.6bpm, clearly bad) was tuned on the
  92 non-motion-pool subjects only; 2SR used the same fixed forehead box as
  CHROM/POS with no skin mask, which its source paper prefers; some v2 strata have as
  few as 3-5 subjects; a mid-run power cut interrupted extraction but the script
  resumed cleanly (0 failures, 0 parity mismatches vs cached production traces).
  **Net effect: production CHROM/POS pipeline is unchanged, nothing promoted.** Full
  detail, per-subject and stratified tables: `matlab/docs/Segment22_Motion_Robust_Combiner_Evaluation.md`,
  `results/metrics/segment22_per_subject.csv`, `segment22_stratified_summary.csv`,
  `segment22_stride_selection.csv`. New code (kept, not wired into production):
  `src/roi/extractROICovariance.m`, `src/pulseextraction/spatialSubspaceRotation.m`,
  `src/pulseextraction/lgiProjection.m`. This closes the motion-robustness line opened
  by Segment 18 — no further combiner work is queued on it; a future session should
  read `matlab/docs/Literature_Review_Master.md` before starting a new search rather
  than re-trying PBV/OMIT, which were already deprioritized in Segment 21 for
  documented reasons (calibration requirement; validated for compression-robustness,
  not motion).
- **[2026-09-20, Segment 23 — fairness / native-form audit of every "EVALUATED, NOT ADOPTED" candidate] CLOSED. Production unchanged; nothing promoted.**
  Question: is CHROM/POS's unbroken record real robustness or an artefact of simplified challengers + unmatched tuning? **Answer (`matlab/experiments/segment23_fairness_audit/MASTER_REPORT.md`):
  mostly real robustness, plus a real-but-modest tuning/read-out asymmetry that changes no ranking; NOT a fairness artefact of incomplete challenger implementations.**
  Every challenger re-run in native/completed form still loses (cPACE windowed q̂ T1; CIELab a* with the paper's ROI + KLT + sum-normalised Lab T2 — native form is *worse*, 16.5 vs 9.5bpm; 2SR with a real YCbCr skin mask T3; LGI with its own read-out + a state-space tracker T4; RAKF with the Eq. 12 exponent T7 — slightly worse than the division form, 11.95 vs 10.73bpm). The 19-combiner × 6-read-out matrix (T5) shows no challenger beats CHROM/POS under the same read-out. De-tuning CHROM/POS (T6) costs 1.3–4bpm pooled MAE but is **not per-subject significant** (all p ≥ 0.08). Per-subject, a\*/2SR/LGI are not significantly worse than CHROM on MAIN_112 (p 0.07–0.36); on the 20-subject motion pool CHROM significantly beats 2SR/LGI/cPACE Full (p 0.010–0.018).
  ~~**New CANDIDATE (not promoted, needs held-out validation e.g. UBFC-D2):**~~ **[2026-09-20, Segment 24: held-out validation run — as-tested candidate NOT validated, see the Segment 24 Current State entry below]** **Original text:** a windowed peak read-out (0.5–2Hz, 256-sample/90%, median) or a frequency-state tracker lowers MAIN_112 MAE of the incumbents 1.1–1.5bpm (CHROM 7.83→6.38/6.54, POS 7.22→6.70/6.29), confounded by the ≤120bpm band prior it carries. **Brief corrections found from primary sources**: Yang's cells are 20×20px (120×80 is the ROI); Kaur's paper does not specify a windowed q̂; Pilz's own benchmark read-out is a 256/90% FFT peak-pick, not the tracker; Debnath & Kim give no numeric β; de Haan & Jeanne (CHROM) primary text was BLOCKED. Also: Segment 22's forehead-only 2SR region was unfairly small on motion (widening helps, still loses). Protected files: 18/18 SHA-256 identical before/after. Full per-task reports: `matlab/experiments/segment23_fairness_audit/task{1..7}_*/REPORT.md`.

- **[2026-09-20, Segment 24 — held-out validation of the Segment 23 read-out candidate] CLOSED. Production unchanged; nothing promoted.** Pre-registered one-shot run (`matlab/experiments/segment24_readout_heldout_validation/PREREGISTRATION.md`, commit `7ffc964`, before any read-out ran). **Step 0 found UBFC-D2 was NOT untouched** (Segment 14 used it for the Branch 2 gate; it was never used for HR-accuracy scoring or read-out selection) and **VIPL-HR-V1 has no unused subjects** (exactly p1–p107, all in MAIN_112). So: PRIMARY = unused VIPL *videos* (source1 webcam v7 cached + v4/v6 newly decoded, 281 videos, 96 people) — **held out by video/scenario, NOT by subject**; UBFC-D2 (42) = SECONDARY, descriptive only; phone source2 strata (321) exploratory. **Results (PRIMARY, person-level paired Wilcoxon, Holm over 8):** windowed read-out as tested in Segment 23 (0.5–2 Hz) does **not** clearly beat production `fftHeartRate.m` (CHROM 11.94→11.47, POS 11.79→11.54 bpm; p_Holm = 1.0) — EVALUATED, NOT ADOPTED as tested; state tracker does not either (gain −0.06…+0.72) — EVALUATED, NOT ADOPTED, its Segment 23 gain does not reproduce. **The band confound was the wrong way round:** the same windowed read-out band-matched to 0.7–4.0 Hz clearly beats production (CHROM →9.21, POS →8.64 bpm; p_Holm 0.0019 / 3e-5) — the ≤120 bpm cap is the liability (it loses on after-exercise clips, GT up to 132 bpm). That band-matched variant was only a control condition, never run on MAIN_112 or a fresh set: **CANDIDATE, NOT VALIDATED**, needs a MAIN_112 run and a fresh set before any claim. D2 (descriptive) agrees in direction. Also found: tracker band is 0.7–3.0 Hz (≤180 bpm), not ≤120 as the brief said. Full report: `matlab/experiments/segment24_readout_heldout_validation/REPORT.md`. Reusable caches: 190 new `data/processed/VIPL_p*_v{4,6}_source1_rgb_traces.mat`, `results/s24_set_manifest.csv` (644 videos), `results/s24_hr_per_video.csv`. Protected files: 18/18 SHA-256 identical.

- **[2026-09-20, Segment 25 — replication of Segment 24's band-matched windowed read-out] CLOSED. Production unchanged; nothing adopted.** Pre-registered one-shot (`matlab/experiments/segment25_readout_replication/PREREGISTRATION.md`, commit `aef3beb`), candidate = `lgiPaperReadout(pulse, fs, [0.7 4.0])` byte-identical to Segment 24's, six paired Wilcoxon tests, one joint Holm. The 321-phone-clip set was audited and EXCLUDED (same 107 people as MAIN_112, prior Branch 1 HR scoring, and condition (c) already seen on it in Segment 24). **(A) MAIN_112 (112): holds** — CHROM 7.83→6.73, POS 7.22→6.45 bpm, not significant on its own, no regression. **(B) VIPL v3+v5 source1, 188 new clips (96 people): replicates** — CHROM 9.43→7.12 (Holm p 0.020), POS 10.27→7.49 (p 0.0007); mostly driven by v5 dark/low-fps (~16.7 fps), weak for v3 on CHROM. **(C) VIPL v1 source3 RealSense, 107 clips: does NOT replicate** (0.11 / 0.43 bpm, n.s.). ~~**Verdict: CANDIDATE, VALIDATED (scenario-generalizing) — not ADOPTED**~~ **CANDIDATE, VALIDATED — degraded-signal conditions only (dark/low-fps/motion; not shown in normal-lighting or cross-device conditions) — not ADOPTED.** **[2026-09-20, Segment 26 Step 0 wording correction] Basis:** the Segment 25 gain splits by scenario — v3 talking CHROM shows no effect (p = 0.89; POS p = 0.030 uncorrected, would not survive correction) versus v5 dark CHROM p = 0.0001 (uncorrected; POS 0.0016), and MAIN_112 (normal lighting) improves without significance (Holm p 0.52–0.997); Segment 24's PRIMARY set shows large gains on v4 (bright light) and v7 (after exercise) and a small one on v6 (stable, 1.5 m) — **note: those Segment 24 scenarios are bright-light / after-exercise / longer-distance, NOT head-motion (VIPL's motion scenarios are v2/v9, not part of Segments 24/25), so 'motion' in the wording above is the requested label, not something these clips demonstrate.** Device shift (v1 source3) did not replicate. (~~CANDIDATE, NOT VALIDATED~~ from Segment 24). Only the read-out stage is new; combiner still CHROM/POS; held out by video/scenario, not by subject; no device-generalization claim. Report: `matlab/experiments/segment25_readout_replication/REPORT.md`. New caches: 295 `data/processed/VIPL_p*_v{3,5}_source1_*` / `_v1_source3_*_rgb_traces.mat`. Protected files 18/18 identical.

- **[2026-09-20, wavelet-denoise promoted into the shared orchestrator; SpO2 pinned pre-wavelet] COMMITTED.** **Bug:** Segment 8 Action 7's wavelet default (`filtering/waveletDenoise.m`) was wired into `run_segment3_filtering_batch.m` / `run_vipl_integration_batch.m` but never into `pipeline/estimateVitalsAndMorphology.m`, the orchestrator every other caller uses, so those callers ran without it. **Fix:** `opts.useWaveletDenoise` (default true) applied immediately before `detrendSignal`; `run_spandan_interactive.m` aligned. **Verification (all 112 cached subjects, 5 UBFC + 107 VIPL, orchestrator run with wavelet on and off vs frozen CSVs at their stored precision):** HR-CHROM and HR-POS frozen values are wavelet-ON (112/112 both); pooled MAE recomputed CHROM 7.8344 / POS 7.2217, so Segment 23-26 HR numbers stand. **GREEN:** `segment6_hr_pooled_metrics.csv`'s GREEN column is a Segment 8 splice artifact (CHROM/POS spliced in wavelet-on; GREEN left pre-wavelet because the ablation never covered it); it is ~~14.98 MAE (MAIN_112)~~ superseded, not because of a new bug but because it was never reconciled. GREEN now follows the wavelet-on default (recomputed MAIN_112 MAE 16.18); no verdict rests on it. Segment 23's own GREEN rows are a self-contained pre-wavelet chain, untouched. **SpO2:** frozen `segment5_dataset1_calibration.csv` and `segment5_vipl_calibration.csv` R values (112/112) match the PRE-wavelet chain, so `calibrateSpO2`'s coefficients were fit on pre-wavelet R. To avoid a train/serve mismatch the orchestrator's SpO2 path is pinned to the pre-wavelet chain regardless of `useWaveletDenoise` (note: the whole detrend/bandpass chain is rebuilt from pre-wavelet R/G/B, not only the DC argument, since `ratioOfRatios` also consumes the filtered AC channels); R values are now bitwise-equal with the flag on or off and equal to the frozen CSVs. **OPEN, DEFERRED:** whether wavelet helps or hurts SpO2 (needs a recalibration + LOSO), and how Branch 2's notch detection behaves under wavelet (UNVALIDATED; `segment7_task_b_notch_branch2.csv` was generated by an independent script that never had wavelet and is a valid frozen baseline, untouched). Both preregistered, not run: `matlab/experiments/segment27_branch2_wavelet_evaluation/PREREGISTRATION.md`. **Test:** `tests/segment7_task_f_regression_test.m` Part 1 no longer gates on GREEN (comment explains); Part 2 passes at the default; Part 3 forces `useWaveletDenoise=false`. Part 1 is weak evidence for wavelet (5-gt CHROM/POS are identical either way). Segments 23-26: only mention of SpO2 is Segment 25's "not tested"; GREEN appears only as a Segment 23 contrast row from its own chain.
- **[2026-09-20, Segment 26 — read-out mechanism isolation] CLOSED. Production unchanged.** Step 0: Segment 25's verdict wording corrected (old struck through) to "CANDIDATE, VALIDATED — degraded-signal conditions only (dark/low-fps/motion; not shown in normal-lighting or cross-device conditions)"; recorded that Segment 24's v4/v6 are bright-light/1.5 m, NOT motion. Pre-registered addendum (`matlab/experiments/segment26_readout_mechanism/PREREGISTRATION_addendum.md`, commit `1bb7d0c`). **Step 1 (median vs mean per-window aggregation, 730 cached clips, 0 new decode, 14 paired Wilcoxon + Holm): median-rejection hypothesis NOT supported.** Mean recovers 101 % (CHROM) / 86 % (POS) of the median's gain on the pooled degraded strata (v4/v6/v5); the median's small edge is, if anything, on the clean strata (mean worse by 0.2–1.0 bpm); no difference significant after correction (all Holm p ≥ 0.078); on v5 dark the mean is nominally better. Windowing itself does most of the work. **Step 2 (Spearman of per-clip gain vs cached proxies fs / dropped-frame fraction / mean ROI green, 6 tests Holm): no correlation** (all Holm p ≥ 0.079, max |ρ| 0.094); frame rate does not order the gains (v3 and v6 same fs, different gains; v4 and v5 opposite fs, similar large gains). **Net: mechanism of *where* it helps still unknown; the quality-gated production-gating story is NOT supported by any proxy available today** — no gating segment warranted on this evidence. Report: `matlab/experiments/segment26_readout_mechanism/REPORT.md`. Protected files 18/18 identical.

- **[2026-09-20, Segment 27 — proposed third mechanism-isolation attempt] DESIGNED BUT DELIBERATELY NOT RUN.** Segment 27 (a proposed third mechanism-isolation attempt for the Segment 24–26 read-out finding) was designed but deliberately NOT run — after two dedicated segments (26's median-vs-mean and quality-proxy tests) came back negative, further mechanism-hunting was judged to have hit diminishing returns with no production decision pending on the answer. Final resting verdict: CANDIDATE, VALIDATED — degraded-signal conditions only; mechanism unresolved; not adopted; no further investigation planned absent new evidence. Full consolidated summary of Segments 23–26: `matlab/docs/Fairness_Audit_Summary_Segments23-26.md`.

---

## Active Work Queue

- [x] **Segment 26 (read-out mechanism isolation) — Done 2026-09-20.** Outputs: `matlab/experiments/segment26_readout_mechanism/{PREREGISTRATION_addendum.md,REPORT.md,results/*,scripts/*,src/lgiPaperReadoutMean.m}`. ~~Open from Segment 25: isolate median-aggregate vs whole-clip FFT same band~~ median-aggregate isolated (not the driver). **Still open, not started:** whole-clip FFT with the same 0.7–4 Hz band/zero-padding (windowing vs band-limit), window length/hop, a genuine signal-quality proxy (spectral SNR, cross-ROI PLV), production-integration swap-in test.
- [x] **Segment 25 (read-out replication) — Done 2026-09-20.** Outputs: `matlab/experiments/segment25_readout_replication/{PREREGISTRATION.md,REPORT.md,results/*,scripts/*,src/*}`. ~~Verdict CANDIDATE, VALIDATED (scenario-generalizing), not ADOPTED.~~ Verdict CANDIDATE, VALIDATED — degraded-signal conditions only (dark/low-fps/motion; not shown in normal-lighting or cross-device conditions), not ADOPTED (wording corrected in Segment 26 Step 0). **Open, not started (a separate decision):** production-integration swap-in test of the windowed 0.7–4 Hz read-out (full Branch 1 chain, Android window/latency check); isolate median-aggregate vs whole-clip-FFT-same-band controls; a genuinely new-people set (Bangladeshi self-collected, PURE/COHFACE/MMPD) if a subject-level claim is wanted.
- [x] **Segment 24 (read-out held-out validation) — Done 2026-09-20.** Outputs: `matlab/experiments/segment24_readout_heldout_validation/{PREREGISTRATION.md,REPORT.md,results/*,scripts/*,src/*}`; new caches `data/processed/VIPL_p*_v{4,6}_source1_rgb_traces.mat` (190). Verdict: as-tested candidate EVALUATED, NOT ADOPTED; band-matched windowed read-out = CANDIDATE, NOT VALIDATED. **Open follow-ups (not started):** run band-matched windowed read-out on MAIN_112; test on a fresh set; band-alone control (whole-clip FFT 0.5–2 Hz) and median-aggregate isolation.
- [x] **Segment 23 (fairness / native-form audit, 7 tasks) — Done 2026-09-20.** Outputs: `matlab/experiments/segment23_fairness_audit/MASTER_REPORT.md`, `task1..task7_*/REPORT.md`, per-task `results/*.csv`, shared `common/` (pool/metrics helpers, `protected_files_verification.txt`, run logs). New caches: `data/processed/seg23t2_<id>.mat` (native CIELab/KLT pass, 132 files), `seg23t3_<id>.mat` (skin-masked pixel stats, 132 files). Verdicts: all seven candidates remain EVALUATED, NOT ADOPTED; one new read-out CANDIDATE (see Current State). Heavy tasks 2 and 3 ran concurrently after a capacity check (both 0 failures / 0 parity mismatches); Tasks 1 and 4 verified LIGHT (cached RGB suffices). Nothing further is queued.
- [x] ~~Segment 22 (queued, not started) — implement + stratified-evaluate motion-robust
      combiners (2SR first, LGI second) against Segment 18's motion-pool finding.~~
      **Done 2026-09-20. Verdict: NO-GO for both 2SR and LGI (projection-only) —
      neither beats production CHROM/POS on the v2 motion pool or the main pool, in
      pooled or stratified results. Production pipeline unchanged.** See the Current
      State entry above and `matlab/docs/Segment22_Motion_Robust_Combiner_Evaluation.md`
      for full per-subject/stratified tables and caveats. LGI's state-space tracker
      was not built (projection step alone already lost). This closes the
      motion-robustness investigation opened by Segment 18/21 — nothing further is
      queued on it.

**Three exploratory pilots, all done 2026-09-13** (Spandan Field Guide "still open"
list — scoped down to small samples on purpose, feasibility/direction-finding, NOT
scaled to the full pool). None of these are adopted/production changes — see each
item's own verdict.

- [x] **Field Guide Action 1 — Multi-region ROI on Android, feasibility prototype.**
      **Done 2026-09-13. Verdict: PROMISING.** New debug-only
      `MultiRegionProfilingFaceAnalyzer` (gated behind a `secondRegionEnabled` flag,
      never wired into the live pipeline) measured the real on-device cost of adding a
      second (cheek) ROI crop-and-average pass alongside forehead, on the same Galaxy
      A35 used for Segment7_Task_G. **Real result: 13.43fps → 13.35fps steady-state**
      (a ~0.6% difference, within normal run-to-run noise) — the added cheek pass costs
      ~0.47ms/frame, negligible next to detection's ~71.5ms. A bigger port (wiring
      forehead+cheek into the live HR pipeline) is NOT blocked by throughput; whether it
      would improve accuracy is a separate, untested question. `MainActivity.kt`
      temporarily wired twice for the two captures, reverted both times (`git status`
      confirms zero diff). Full detail:
      `android/docs/Segment9_Task1_MultiRegion_ROI_Feasibility_Pilot.md`. New files:
      `android/app/src/main/java/com/spandan/app/camera/MultiRegionProfilingFaceAnalyzer.kt`,
      plus additive `cheekRoisFrom`/`averageRgbMultiRect` functions added to
      `RoiCalculator.kt`/`RoiPixelAverager.kt` (their existing forehead/single-rect
      functions unchanged).
- [x] **Field Guide Action 2 — RAKF parameter sweep, small pool (10 subjects).** **Done
      2026-09-13. Verdict: NO (sweep does not rescue RAKF).** First fetched Debnath &
      Kim's actual paper (PMC12818640) and found real numbers never checked before:
      R0=25, Q=2e-4 (both per-frame @ 30fps, fixed across datasets) — and a genuine
      MECHANISM mismatch worth flagging, not fixed: the paper's Eq. 12 uses an EXPONENT
      (`R0*(1+|innovation|^beta)`), this port uses DIVISION
      (`R0*(1+|innovation|/beta)`). Swept 48 (R0,Q,beta) combinations on 10 cached VIPL
      subjects (p1-p10, no video reprocessing). **Best combo (R0=5, Q=1, beta
      multiplier=2) gives MAE 5.22→4.80 on this sample (~8% relative)** — a real but
      small improvement, and in the direction of "trust raw measurements more, smooth
      less," which CONFIRMS rather than overturns Task 5's original verdict (the
      simplest, least-smoothed methods already win on this data). Full detail:
      `docs/Segment9_Task2_RAKF_Param_Sweep_Pilot.md`. New files:
      `matlab/scripts/run_segment6_task5b_rakf_param_sweep_pilot.m`,
      `results/metrics/segment6_task5b_rakf_sweep_pilot.csv`.
- [x] **Field Guide Action 3 — Smarter region-switching rule, small pool (v2/v5
      scenarios only).** **Done 2026-09-13. Verdict: AMBIGUOUS (small,
      scenario-dependent).** New `validation/computeRegionSwitchingEstimateWeighted.m`
      (standout-check-first, then a forehead/cheek-weighted vote fallback), alongside
      (not replacing) the existing switcher. Tested on Task N's already-cached v2
      (motion) and v5 (dark) scenarios (20 subjects each). **Found and reported an
      honest discrepancy along the way**: recomputing the EXISTING switcher fresh from
      `segment6_task_n_region_hr_summary.csv` gives MAE 7.0712 (v2) / 4.6654 (v5), not
      the doc's cited 7.72/4.79 — flagged, not investigated further (out of this
      pilot's scope). Same-data comparison: **v5 — small real win** (NEW 4.6102 beats
      both the fresh existing-switcher number 4.6654 and cheek-alone 4.9763, though
      RMSE is very slightly worse). **v2 — flat to very slightly worse** (NEW 7.1825 vs.
      existing 7.0712, both still beat forehead-alone 8.1821). Selection-count check
      confirms the mechanism works as designed (cheek picked 5/20 vs. the old rule's
      1/20 in v5, where cheek genuinely is the best region). Full detail:
      `docs/Segment9_Task3_Weighted_Region_Switching_Pilot.md`. New files:
      `matlab/src/validation/computeRegionSwitchingEstimateWeighted.m`,
      `matlab/scripts/run_segment6_region_switch_weighted_pilot.m`,
      `results/metrics/segment6_region_switch_weighted_pilot.csv`.

**None of the three pilots above are adopted** — all are additive, gated, or
small-sample-only per their own scope; nothing already in production
(`Current State` above) changed because of them. When/if a future session decides to
scale any of these up, that is a new, explicit decision, not an automatic next step.

- [x] **Segment 10 Task 1 — Full rPPG-vs-ground-truth-PPG waveform &amp; frequency
      fidelity audit.** ~~Queued 2026-09-13 (Cowork planning session), not yet
      started~~ **[2026-09-13] DONE, 100/100 subjects succeeded, 0 failures.**
      Ran on the full Task K pool (5 UBFC-D1 + 95 VIPL v1/source1), reusing cached
      `_rgb_traces.mat` for every subject — no video reprocessed. **Headline
      findings**: (1) a new broadband lag-search method
      (`morphology/estimateLagPolarityByGroundTruth.m`, new/additive) is itself
      unreliable 34-46% of the time (flagged, not dropped, per subject) —
      disproportionately for the harmonic-comb branch, whose comb construction
      makes it more periodic and hence more alias-prone; (2) pooled waveform
      correlation is modest for all three signals (median r 0.44-0.52), with the
      harmonic-comb branch highest-median but also highest-variance (bimodal
      reliability, not a clean win) — independent evidence for, not against, this
      project's existing decision to keep Branch 1/Branch 2 separate; (3) the
      harmonic-confusion detector independently reproduces the known VIPL_p21
      CHROM anecdote exactly (ratio = 2.00) and finds Branch 2 confused 4-5x more
      often than Branch 1 at every tolerance tried (1/100 vs 5/100 at the primary
      ±8% tolerance); (4) after rigid-lag removal, ~40-47% of the pool still shows
      real fundamental-band phase distortion (not just delay); (5) mismatch energy
      concentrates in the fundamental/2nd-harmonic bands, not in noise; (6)
      `notchDetectIEM.m`'s boolean output is a useless gate at pool scale
      (100/100 "detected") — using this project's own 0.3 confidence bar instead,
      only ~26-28% of the pool (VIPL-dominated) shows a confident GT notch, a new
      caveat on generalizing Task B's 4/5-UBFC notch result. Full detail, all
      caveats, and the worst-5/best-5 worked examples:
      `docs/Segment10_Task1_Waveform_Fidelity_Audit.md`. Outputs:
      `results/metrics/segment10_waveform_fidelity_per_subject.csv`,
      `..._pooled_summary.csv`, `results/figures/segment10_*.png` (4 figures),
      `scripts/run_segment10_waveform_fidelity_audit.m`,
      `src/morphology/estimateLagPolarityByGroundTruth.m`. Read-only diagnostic —
      confirmed none of the "do not touch" files below were modified. Went past
      every HR-accuracy number already on record to compare actual waveform
      *shape*, not just the FFT-peak-derived bpm number, against real ground
      truth — full original scope (as handed to the executing session) preserved
      verbatim in `docs/Segment10_Task1_Waveform_Fidelity_Audit.md`'s own Method
      section rather than duplicated here a second time.
- [x] **Segment 10 Task 2 — Solution literature search for Task 1's six findings.**
      **Done 2026-09-13 (Cowork planning session). No code written, nothing run.**
      Searched papers/GitHub for real prior work addressing each of Task 1's six
      findings; every citation carries an explicit access marker
      (VERIFIED-FULL / VERIFIED-INDEX / BLOCKED) per this project's standing
      citation-verification discipline. Full writeup:
      `docs/Segment10_Task2_Solution_Literature_Search.md`. **The single most
      important result is not a fix but a reframing**: the same arXiv:2606.03802
      template-collapse paper Task K already checked makes a SECOND claim Task K
      never tested — a ground-truth waveform-correlation ceiling of r≈0.601, and a
      sampling-rate argument that the dicrotic notch (~50-100ms) spans only 1-3
      samples at 30fps, i.e. at or below the joint temporal-resolution/SNR floor.
      Task 1's measured median r of 0.44-0.52 sits just under that stated ceiling,
      so **before implementing anything, run the zero-new-data ceiling test**:
      correlate Task 1's existing per-subject notch confidence against the existing
      per-subject effective-fps figures (already on record from the Segment 8
      source2 work). If notch confidence scales with fps, the ceiling argument
      holds and most candidate fixes below are low-yield. Highest-value candidate
      fix if it doesn't: **Harmonic-Selective Gaussian Filtering**
      (Dominguez-Hernandez, Paez & Padilla, *Sensors* 26(12):3710, 2026,
      doi:10.3390/s26123710, read in full) — a Gaussian-tapered, f0-scaled harmonic
      filter that explicitly targets morphology AND timing preservation, i.e. a
      direct structural alternative to `morphology/adaptiveHarmonicFilter.m`'s
      hard-edged comb, whose ringing is a textbook cause of exactly the shape
      distortion Task 1 finding (4) measured. Also queued in that doc, in
      cheapest-first order: a synthetic-notch filter-distortion isolation test,
      harmonic-sum scoring for the harmonic-confusion problem (Dubey/Kumaresan/
      Mankodiya 2018, doi:10.1007/s12652-016-0422-z), GCC-PHAT + sub-band delay
      consistency for the unreliable lag search, and pyPPG/SDPPG as independent
      second opinions on the notch-detection gate. **Nothing in that document is
      implemented or validated — it is a search result, not a finding.**
      ~~Three papers remain BLOCKED (PMC reCAPTCHA) and unread.~~
      **[2026-09-13, REVISION 2 of that doc] All three retrieved and read** (two
      supplied as PDFs by the user in `H:\EEE 312 project\Contactless Vital
      Sign\Research Paper\`, one via nature.com), and one of them **displaces the
      ceiling argument as the headline result**: Kaur, Lakshminarayanan & Saini,
      *Missed isochromatic cardiac pulsation in remote photoplethysmography*,
      **Biomed. Opt. Express 17(7):3832 (2026), doi:10.1364/BOE.599752**. It argues
      the standard rPPG signal model this project is built on is INCOMPLETE: there
      are two cardiac-frequency components, chromatic (haemoglobin absorption, what
      CHROM/POS assume is everything) and **isochromatic** (ballistocardiographic
      skin-geometry + scattering modulation, lying along the skin's mean reflectance
      direction q̂), they sit at the same frequency so **"temporal filtering cannot
      separate them,"** and the isochromatic one carries the MAJORITY of cardiac-band
      energy (median 69-83% across three cohorts). It predicts three of Task 1's six
      findings mechanistically — the respiration-rate phase wobble (finding 4) and
      hence the unreliable lag search (finding 1, possibly physical rather than
      methodological), and the missing 2nd-harmonic structure (finding 5, because the
      isochromatic component has no discernible 2nd harmonic while the chromatic one
      does). It also independently predicts POS > CHROM on fidelity (CHROM's basis is
      never orthogonal to [1,1,1], so it leaks 0.58 even at skin-colour angle 0°) —
      a pattern this project has measured repeatedly and never had a mechanism for.
      **Their fix's first stage is ~5 lines here**: project out q̂ = normalised
      per-channel temporal means (which Spandan already computes for CHROM/POS
      normalisation and SpO2) via `P = I - q̂q̂ᵀ` before pulse extraction. Their
      cPACE vs POS HR MAE: 1.7/3.7/1.7/1.1 vs 2.8/9.5/16.8/17.8 BPM. **Also relevant
      to pipeline stage 7**: leakage grows with skin-colour angle (~5-10° light,
      30-50° dark), so this project's planned Bangladeshi self-collected set is
      predicted to sit at higher θ than either UBFC or VIPL and perform WORSE under
      the current pipeline — worth recording before collecting, not after. Second
      new result: pyPPG (Goda/Charlton/Behar, Physiol. Meas. 45(4):045001) states
      outright that an **8 Hz low-pass ceiling "significantly distort[s] the pulse
      wave shape"** and uses 0.5-12 Hz specifically "to avoid time-shifting of
      fiducial points (particularly pulse onset and dicrotic notch)" —
      `morphology/bandpassMorphology.m` uses exactly 0.5-8 Hz. Combined with the
      ceiling paper's "notch spans 1-3 samples at 30fps," two independent sources now
      converge on **camera frame rate as the binding constraint on notch morphology**
      (at 25-30fps Nyquist is 12.5-15Hz, so a 12Hz passband is barely available at
      all; VIPL scenarios at a real ~16fps have Nyquist 8Hz, BELOW Branch 2's own
      existing ceiling). Revision 2 also adds the GitHub-toolbox assessment
      (rPPG-Toolbox = useful classical cross-check + PBV/LGI/OMIT, non-OSI licence,
      read-don't-copy; open-rppg = deep learning, out of scope; Awesome-rPPG =
      stale bibliography) and a consolidated Tier 0-3 candidate list.
- [x] **Segment 10 Task 3 — Tier 0 diagnostics (four cheap tests, decide if Tier 1 is
      worth starting).** **Done 2026-09-13. 3 of 4 SUPPORTED, 1 NOT SUPPORTED — headline
      is the one that failed.** All four additive/read-only, no do-not-touch file
      modified (verified via `git status`), no video reprocessed. **Action 1 (ceiling
      test) — NOT SUPPORTED**: arXiv:2606.03802's claim that notch confidence should
      scale with true effective fps does not hold within VIPL (n=95, real 16-30fps
      range: r=-0.13 to +0.04, i.e. flat/negative); the apparent positive pooled
      correlation (r=0.13-0.26) is a two-cluster artifact of UBFC (constant ~28.7fps,
      high notch confidence) vs. VIPL (variable fps, uniformly much lower notch
      confidence) rather than a real within-dataset relationship — independently
      re-verified that Task 1's cached `frameRate` really is time.txt-corrected (checked
      p20 against its raw time.txt directly: 16.1374 fps computed = 16.1374 fps cached).
      **Action 2 (cross-ROI PLV, needs no ground truth) — SUPPORTED**: on Task N's cached
      20-subject four-region pool, mean cross-ROI PLV correlates with Task 1's own
      GT-referenced correlation at r=0.571 (CHROM) / 0.632 (POS), n=20 — a real
      ground-truth-free fidelity metric candidate, small-N caveat stated. **Action 3
      (synthetic-notch filter distortion) — SUPPORTED**: a new closed-form two-Gaussian
      synthetic PPG waveform with a known notch shows `bandpassClean.m`'s narrow 0.7-4Hz
      band destroys ~45-50% of notch depth at every fps tested, while the already-adopted
      wide-band `bandpassMorphology.m` (0.5-8Hz) preserves ~97-100% of it when it can run
      — but at a true 16fps (Nyquist=8Hz), that wide-band filter and every 8/10/12Hz
      order-2 variant is literally inadmissible (Nyquist), a real structural gap affecting
      ~~21%~~ **46% (recount corrected 2026-09-13, Segment 12 Task 1 — the
      original count was a genuine error, likely conflated with Segment 6 Task L's
      unrelated 20-subject v5-scenario figure)** of Task 1's own VIPL pool, not a
      tuning question. Order (2 vs 3) is not the
      dominant driver; upper cutoff is, matching Lapitan et al. **Action 4 (POS cardiac
      angle) — SUPPORTED**: measured actual cardiac angle on 25 subjects (5 UBFC-D1 + 20
      VIPL) via PCA on `posCombine.m`'s own un-combined S1/S2 projections (pure
      measurement, `posCombine.m` itself untouched) — median 109.5° (VIPL 121.4°, UBFC
      97.8°), 92% above the 90° destructive-combination threshold, none near POS's
      assumed 57° — lands inside Kaur et al.'s own reported 96.6-115.5° cross-cohort
      range, independently corroborating that paper's isochromatic-contamination
      mechanism on Spandan's own data. **Net verdict: Tier 1 is worth starting, but not
      for the reason Task 2 Revision 1 emphasized** (the sampling ceiling is ruled out) —
      cPACE Stage 1 is now the best-supported next step (direct on-Spandan evidence for
      its target mechanism), cross-ROI PLV is worth adopting as a standing metric, and the
      16fps/Nyquist gap for Branch 2 is a newly concrete open question (`bandpassMorphology.m`'s
      existing but unused `'mid'` mode, 0.6-6.0Hz, is a candidate, not yet tried). Full
      detail: `matlab/docs/Segment10_Task3_Tier0_Diagnostics.md`. Outputs:
      `matlab/scripts/run_segment10_task3_tier0_diagnostics.m`,
      `results/metrics/segment10_task3_tier0_action{1,2,3,4}_*.csv`,
      `results/figures/segment10_task3_action{1,2,3,4}_*.png`. **No Tier 1 work started.**
- [x] **Segment 11 Task 1 — implement cPACE Stage 1 (gated, off-by-default) and promote
      cross-ROI PLV to a standing metric.** **Done 2026-09-13. cPACE: NOT adopted (proven
      no-op for POS, real regression for CHROM). PLV: promoted, adopted as a standing
      tool.** Two highest-value Tier 1 items from Task 3's verdict; no other Tier 1/2/3
      item started. New `pulseextraction/cpaceProjection.m` (off-by-default pre-step,
      never wired into `chromCombine.m`/`posCombine.m` themselves) and
      `validation/computeCrossROIPLV.m` (extracted from Task 3's one-off computation).
      Do-not-touch files confirmed unmodified via `git status`. **Headline finding**: on
      the same 100-subject pool Task 1 used, cPACE Stage 1 is a **provable, exact
      algebraic no-op for POS** — `posCombine.m`'s own `S1`/`S2` basis vectors
      (`[0,1,-1]`, `[-2,1,1]`, both zero-sum) are, after per-channel-own-mean
      normalization, EXACTLY orthogonal to `q_hat` for any subject/skin-tone, a fact
      proven on paper and verified computationally (max per-subject HR diff across all
      100 subjects = exactly 0; max waveform-corr diff = 1.5e-14, floating-point noise).
      For **CHROM**, whose basis vectors are NOT zero-sum, cPACE genuinely changes the
      signal but makes it **modestly worse**: HR MAE 7.86→8.72bpm, pooled HR r
      0.365→0.275, median waveform corr 0.445→0.417 (74/100 subjects regress, one
      severely: `VIPL_p96` 28→98bpm). Neither combiner moves in the direction Kaur et
      al.'s own cPACE-vs-POS comparison (1.7-3.7 vs 2.8-17.8bpm MAE) would suggest —
      explained, not just observed: their comparison is the full 3-stage cPACE against a
      *generic* POS, not Stage 1 alone against Spandan's own *per-subject-adaptive*
      POS. Per-subject skin-colour angle also reported for all 100 (median 8.61°, range
      0.06-15.38°) — squarely inside Kaur et al.'s own "lightly pigmented" range, nowhere
      near their "darkly pigmented" (~30-50°) range where their reported gains are
      largest; POS's invariance is skin-tone-independent (pure algebra, holds for any
      future cohort), CHROM's regression was only measured on this light-skin cohort and
      is not guaranteed to generalize to a future darker-skinned one. **Recommendation:
      cPACE stays an available, OFF-by-default flag — not promoted to default-on for
      either combiner.** Cross-ROI PLV (`computeCrossROIPLV.m`) IS adopted as a standing,
      ground-truth-free validation tool, documented in `README.md`'s folder-structure
      listing for future sessions to find. Full detail:
      `matlab/docs/Segment11_Task1_cPACE_Stage1_and_PLV_Metric.md`. Outputs:
      `matlab/src/pulseextraction/cpaceProjection.m`,
      `matlab/src/validation/computeCrossROIPLV.m`,
      `matlab/scripts/run_segment11_task1_cpace_and_plv.m`,
      `results/metrics/segment11_cpace_before_after.csv`,
      `results/metrics/segment11_cpace_skin_angle_per_subject.csv`,
      `results/figures/segment11_*.png` (4 figures).
- [x] **Segment 12 Task 1 — evaluate `bandpassMorphology.m`'s existing but unused
      `'mid'` mode (0.6-6.0Hz) for the Nyquist-margin problem.** **Done 2026-09-13. Small
      strictly non-regressive win, NOT adopted as default (mechanism doesn't match the
      original hypothesis).** **Correction made first**: Task 3's own "20 of 95 (21%)"
      affected-subject figure was a genuine counting error (~~20~~ **44 of 95, 46%**) —
      corrected in `docs/Segment10_Task3_Tier0_Diagnostics.md` and this file with
      strikethrough. Checked first, per the brief's own instruction: today's `'wide'`
      mode does NOT error for the affected group (real fps is always fractionally above
      the exact 16.0fps that would trip the guard), but runs with a razor-thin margin
      (0.033-0.322Hz) vs. `'mid'`'s comfortable ~2.0-2.3Hz. Regression check: fresh
      `'wide'` recompute matches Task 1's own cached numbers 100/100. Result: only 6/100
      subjects show ANY difference between `'wide'`/`'mid'` (fftHeartRate's fixed
      0.7-4Hz search band is insensitive to this specific band-edge choice for almost
      everyone); of those, 3 flip from failing to passing the 0.3 notch-confidence bar,
      zero flip the other way — but only 1 of the 3 is in the "affected" near-Nyquist
      group (2 of 3 are in the "safe" group), so the improvement is NOT the
      Nyquist-margin fix originally hypothesized, just a small scattered harmonic-lock-
      escape effect. One flip (`VIPL_p14`) shows notch confidence improve while waveform
      correlation regresses — a real per-metric disagreement, stated not hidden.
      **Recommendation: keep production on `'wide'`** (evidence for switching is real
      but weak and untargeted); `'mid'` is now a genuinely validated (not just
      theoretical) low-risk alternative available via `bandpassMorphology.m`'s own
      existing `bandMode` argument, no new file needed. Full detail:
      `matlab/docs/Segment12_Task1_Mid_Band_Evaluation.md`. Outputs:
      `matlab/scripts/run_segment12_task1_mid_band_evaluation.m`,
      `results/metrics/segment12_task1_mid_band_comparison.csv`,
      `results/figures/segment12_task1_*.png` (3 figures).
- [x] **Segment 12 Task 2 — implement and evaluate Harmonic-Selective Gaussian
      Filtering (Dominguez-Hernandez, Paez & Padilla, Sensors 26(12):3710, 2026) as a
      gated alternative to `adaptiveHarmonicFilter.m`'s ABPF comb.** **Done 2026-09-13.
      NOT adopted at the paper's own default parameter; a tuned parameter shows promise
      but has a real per-subject cost, also NOT adopted.** New
      `morphology/harmonicSelectiveGaussianFilter.m` (full formula read from the primary
      source, PMC13307314, this session — not the earlier literature-search summary
      alone), never wired into production. Regression check: fresh ABPF recompute
      matches Task 1's own cached notchConfidence/corr 100/100. **At the paper's own
      literal alpha=0.5 ("a practical compromise" per its authors): underperforms ABPF
      on every metric except a small harmonic-confusion win** — pass rate 20% vs. ABPF's
      24%, median waveform corr 0.383 vs. 0.519 (57-65% of subjects regress on the two
      headline metrics). **Mechanism identified and visualized**: at alpha=0.5, each
      harmonic's Gaussian full-width (~1.18*f0) exceeds the harmonic spacing (f0) itself
      at this pool's typical HR, so adjacent harmonics overlap heavily and the filter
      stops being meaningfully "selective." **Follow-up alpha sweep (0.10-0.50, not in
      the original brief, run because the mechanism predicted it would matter) finds
      alpha=0.15 beats ABPF on all three metrics at once** (pass rate 31% vs 24%, median
      corr 0.523 vs 0.519, harmonic confusion 3% vs 5%) — **but 17/100 subjects show a
      severe notch-confidence regression even as the pool median improves** (several
      dropping from ~1.0 to near-zero), reported plainly rather than only citing the
      favorable median. **Recommendation: adopt neither** — alpha=0.5 is a clear loss,
      alpha=0.15's pool-level win comes with an unexplained 17-subject severe-regression
      tail this project's own evaluation-honesty standard won't paper over. Flagged as
      the most promising unresolved lead in the whole document for a future session
      (investigate the regression-tail subjects, try adaptive/per-subject alpha, or
      combine a tighter alpha with more harmonics). Full detail:
      `matlab/docs/Segment12_Task2_Harmonic_Selective_Gaussian_Filter.md`. Outputs:
      `matlab/src/morphology/harmonicSelectiveGaussianFilter.m`,
      `matlab/scripts/run_segment12_task2_gaussian_harmonic_filter_evaluation.m`,
      `matlab/scripts/run_segment12_task2b_gaussian_alpha_sweep.m`,
      `results/metrics/segment12_task2_gaussian_vs_abpf_comparison.csv`,
      `results/metrics/segment12_task2b_gaussian_alpha_sweep.csv`,
      `results/figures/segment12_task2*.png` (4 figures).
- [x] **Segment 13 — root-cause the Gaussian-filter (alpha=0.15) 17-subject regression
      from Segment 12 Task 2, and fix it if a clean factor emerges.** **Done 2026-09-13.
      Clean factor found; a gated fix built and verified beats both ingredients; NOT
      adopted into production, per the brief.** **Action 1 (root cause)**: pulled
      per-subject results from Segment 10/11/12's own already-validated CSVs (no video
      reprocessed), checked five hypotheses, reported all: dataset (weak, small-N only),
      device/source (inapplicable, no variation in this pool), HR range (overlapping,
      not a separator), skin-colour angle (ruled out, regressor median inside the pool's
      own IQR) — and baseline ABPF pass/fail status, a **clean separator**: all 17/17
      severe regressors were subjects ABPF already passed (>0.3 confidence) before any
      Gaussian filter; 0/76 ABPF-failing subjects showed a severe regression. Conditional
      rate: 17/24 (71%) of ABPF-passing subjects regress severely under Gaussian(0.15);
      0/76 (0%) of ABPF-failing subjects do. Mechanism: several regressors sit at
      `notchDetectIEM.m`'s own documented confidence-clip ceiling (1.000), which has more
      room to fall than a low-confidence subject has room to rise; waveform correlation
      (uncapped) does NOT show the same one-sided pattern for these same subjects.
      **Action 2 (gated fix)**: new `morphology/harmonicFilterConfidenceGate.m` (generic,
      reusable, never wired into `pipeline/estimateVitalsAndMorphology.m` or any
      production call site) — keep ABPF wherever it already passes; substitute
      Gaussian(0.15) only where ABPF fails. Evaluated on REAL freshly recomputed signals
      (not just cached-CSV arithmetic): pass rate 24%(ABPF)/31%(Gaussian alone)/**47%
      (gated)**, median notch conf 0.058/0.090/**0.235**, median waveform corr
      0.519/0.523/**0.522**, harmonic confusion 5%/3%/**3%**, severe regressions vs. ABPF
      17(Gaussian alone)/**0 (gated, by construction)**. Honest cost still on record:
      among the 76 substituted subjects, corr improves for 45, regresses for 31 (not
      severe by the notch metric, since none were passing to begin with). **Also tested
      and explicitly warned against**: a multi-candidate variant (pick whichever of
      several Gaussian alphas self-reports the highest confidence) pushes pass rate to
      64% but its median corr (0.508) is the WORST of every method compared — a
      demonstrated selection-bias artifact from repeatedly picking the highest of several
      noisy self-scores, not a real gain; the new gate function's own header states this
      warning so it isn't rediscovered later. **Recommendation: the safe gate is the
      best-supported single result in the whole cPACE/mid-band/Gaussian-filter
      investigation line, but stays gated and off-by-default, not adopted, per the
      brief.** Full detail:
      `matlab/docs/Segment13_Task1_Gaussian_Regression_Root_Cause_and_Gate.md`. Outputs:
      `matlab/src/morphology/harmonicFilterConfidenceGate.m`,
      `matlab/scripts/run_segment13_task1_regression_root_cause.m`,
      `matlab/scripts/run_segment13_task2_gated_selection_evaluation.m`,
      `results/metrics/segment13_task1_regression_root_cause.csv`,
      `results/metrics/segment13_task2_gated_evaluation.csv`,
      `results/figures/segment13_task1_*.png`, `results/figures/segment13_task2_*.png`.
- [x] **Segment 14 — held-out validation and production promotion of the confidence
      gate.** **Done 2026-09-13. PROMOTED.** `pipeline/estimateVitalsAndMorphology.m`'s
      `opts.useConfidenceGate` now defaults to `true`, replacing plain ABPF as Branch 2's
      production default. **Action 1 (held-out data)**: found and used UBFC DATASET_2 (42
      subjects, real ground-truth PPG, confirmed via `docs/DATA_FORMAT.md` and Segment 7
      Task K's own changelog entry to have NEVER been extracted/decoded/evaluated anywhere
      in this project) — extracted via the same targeted per-entry zip technique this
      project uses for VIPL (44GB used, 44GB still free afterward). Ran the exact Segment
      13 comparison (ABPF/Gaussian015/gate) unmodified. Found and root-caused a genuine
      data-quality issue along the way: 9/42 subjects' own `ground_truth.txt` files
      contain a duplicate timestamp, tripping `resampleUniform.m`'s `interp1(...,'pchip')`
      (an existing, unmodified function — not a bug introduced here) — excluded, not
      silently worked around, leaving n=33 valid. **Result: the gate's defining property
      (zero severe regressions) replicated exactly on held-out data** — pass rate
      45%(ABPF)→58%(gate), median corr 0.364→0.520, vs. plain Gaussian(0.15) alone's 13
      severe regressions out of 33 (39%, proportionally worse than the audit pool's 17%).
      Full detail: `matlab/docs/Segment14_Task1_UBFC_D2_Held_Out_Validation.md`.
      **Action 2 (wiring)**: checked first, per the brief — `run_segment3_filtering_batch.m`
      / `run_vipl_integration_batch.m` do NOT call `adaptiveHarmonicFilter.m` at all (they're
      Branch 1-only); `run_spandan_interactive.m` has its own standalone embedded copy, left
      untouched (demo script, not a production metrics source). The real orchestrator,
      `pipeline/estimateVitalsAndMorphology.m`, got the new `opts.useConfidenceGate`
      (default `true`) toggle: Gaussian(0.15) is computed and the gate consulted ONLY when
      ABPF's own confidence fails the 0.3 bar (cheap in the common case). New provenance
      fields (`harmonicMethodUsed`, `gateSubstituted`, `abpfNotchConfidence`,
      `gaussianNotchConfidence`) added to `branch2`/`result.notch`.
      `tests/segment7_task_f_regression_test.m` updated to pin its ABPF-specific Part 3
      check to `useConfidenceGate=false` (testing that condition BY NAME) — **re-run,
      confirmed all 3 parts (Branch 1 HR, Branch 1 SpO2, Branch 2 notch) still PASS**.
      `run_segment7_task_b_branch2_batch.m` (the script generating the cited
      `segment7_task_b_notch_branch2.csv`) updated additively with a new `confidenceGate`
      condition row per subject; old file preserved as
      `segment7_task_b_notch_branch2_preconfidencegate.csv`. **Honest finding on that same
      5-subject legacy benchmark: the gate makes ZERO difference (still 4/5 pass)** — only
      1 of 5 subjects (`after-exercise`) is even eligible for substitution (ABPF already
      passes the other 4), and that one isn't rescued either (0.1582→0.0011, still
      failing) — stated plainly, not implied to have improved. **Action 3 (Android)**:
      checked, not guessed — confirmed directly from `android/docs/
      Defense_Readiness_Checklist.md` and `Segment7_Task_G_Throughput_Profiling.md` that
      ~~Branch 2 (`adaptiveHarmonicFilter`, `ensembleAverageBeats`, `notchDetectIEM`) has
      NEVER been ported to Android, by deliberate prior scope decision~~ **[2026-09-15/16,
      Segment 19] SUPERSEDED — Branch 2 has now been ported** (new
      `AdaptiveHarmonicFilter.kt`/`HarmonicSelectiveGaussianFilter.kt`/`NotchDetectIEM.kt`/
      etc., orchestrated by `MorphologyWaveformEstimator.kt`, verified live on-device — see
      the Segment 19 entry below). True as stated at the time this Segment 14 entry was
      written (2026-09-13, when this promotion itself was correctly MATLAB-only) — no
      longer the current state. Full detail:
      `matlab/docs/Segment14_Task2_Confidence_Gate_Production_Promotion.md`. Outputs:
      `matlab/scripts/run_segment14_task1_ubfc_d2_held_out_validation.m`,
      `results/metrics/segment14_task1_ubfc_d2_held_out_validation.csv`,
      `results/figures/segment14_task1_held_out_summary.png`,
      `data/raw/UBFC-rPPG/DATASET_2/` (42 subjects, newly extracted),
      `data/processed/UBFC_D2_subject*_rgb_traces.mat` (42 subjects, newly cached),
      `results/metrics/segment7_task_b_notch_branch2.csv` (regenerated),
      `results/metrics/segment7_task_b_notch_branch2_preconfidencegate.csv` (snapshot).
      Modified: `matlab/src/pipeline/estimateVitalsAndMorphology.m`,
      `matlab/tests/segment7_task_f_regression_test.m`,
      `matlab/scripts/run_segment7_task_b_branch2_batch.m`, `README.md`,
      `matlab/docs/Spandan_Final_Pipeline_Report.md`.
- [x] **Segment 15 — cPACE Stages 2-3 (eigenvector selection + homodyne normalization),
      built on top of Segment 11 Task 1's Stage 1.** **Done 2026-09-14. NOT adopted,
      kept gated/off-by-default.** Briefed as "Segment 14" — corrected to Segment 15
      before writing any code, since Segment 14 (above) already exists and is
      unrelated. **Two things checked against the actual paper (both PDFs — main
      paper and Supplement 1 — are in `Research Paper/`, read directly, not assumed
      from the brief) before implementing**: (1) the brief's claim that the paper has
      "no second candidate" for eigenvector selection is WRONG — Section 4.2 describes
      a two-candidate multi-ROI PLV consensus (cPACE-v1 vs. cPACE-absorption); asked
      the user directly, decided to implement dominant-eigenvector-only anyway (Table
      S2's own literal row, and this project only has multi-ROI data for a 20-subject
      pool, not the full 100). (2) The paper's own Table S2 parameters (bw=0.30Hz,
      fenv=0.30Hz, kappa=2, 0.7-3.0Hz cardiac band, order-4/order-2 filters, etc.) were
      verified directly against the real Table S2 in Supplement 1 — all matched the
      brief exactly. **New functions**: `pulseextraction/cpaceEigenExtract.m` (seed
      from green-channel PSD peak, narrowband seed+/-bw covariance, dominant
      eigenvector) and `cpaceHomodyneNormalize.m` (Hilbert envelope/phase, envelope
      lowpassed at fenv, demodulated with gate exponent kappa). **One real ambiguity
      found and fixed via real-data testing**: a first implementation, following the
      paper's Eq. 9 literally (`s(t) = v1^T x_c(t)`, the WIDE 0.7-3.0Hz signal),
      gave HR MAE 16.2bpm (vs. production ~7.9bpm) because a 2.3Hz-wide signal isn't
      close enough to monocomponent for Hilbert instantaneous phase to be
      meaningful — the same precondition `computeCrossROIPLV.m`'s own header already
      documents. Fixed by projecting the narrowband seed+/-bw signal (the same one v1
      was derived from) instead — MAE improved to 10.1bpm at bw=0.30, still a net
      regression but no longer clearly broken. Documented as a resolved ambiguity in
      the function's own header, since Table S2 is silent on which signal feeds this
      step. **Task 3 (bw sweep, {0.15, 0.30, 0.50}Hz, real 100-subject pool, per-subject
      not just pooled)**: confirms bw is the sensitive parameter the paper's own
      Supplement flags, but the real per-subject swings (up to ~40bpm for two UBFC-D1
      subjects at bw=0.50) are far larger than the paper's own reported pooled
      0.99-2.88bpm swing — a pooled table alone would have hidden this, the same
      lesson as Segment 12's 17-subject regression. Narrower (bw=0.15) is pooled-best
      on this project's mostly-resting cohort, consistent with the paper's own caution
      that a fixed narrow eigen-window fits a narrow-HR-range cohort well but may not
      generalize. **Task 4 (full pipeline vs. production/Stage-1-only)**: full cPACE
      does not beat production POS/CHROM at any bw tested (best pooled: 8.66bpm at
      bw=0.15 vs. 7.86-7.87bpm production); 42/100 subjects regress >1bpm vs. POS,
      24/100 severely (>10bpm) — several already-accurate (<3bpm) subjects made badly
      wrong. Cross-ROI PLV (20-subject VIPL pool) DOES improve slightly at every bw
      (0.279-0.295 vs. production's 0.254-0.271) — a genuine phase-coherence gain even
      though HR-MAE regresses on this light-skinned, low-motion cohort, consistent with
      Segment 11's own finding that this project's cohort sits in the paper's
      least-favorable (low skin-colour-angle) regime. **Kept gated/off-by-default**,
      same discipline as `cpaceProjection.m` and the gate's own multi-candidate mode.
      Full detail: `matlab/docs/Segment15_Task1_cPACE_Eigen_Extract.md`,
      `Segment15_Task2_cPACE_Homodyne.md`, `Segment15_Task3_Hyperparameter_Sweep.md`,
      `Segment15_Task4_Evaluation.md`. Outputs:
      `matlab/src/pulseextraction/cpaceEigenExtract.m`,
      `matlab/src/pulseextraction/cpaceHomodyneNormalize.m`,
      `matlab/scripts/run_segment15_task3_task4_cpace_full_evaluation.m`,
      `results/metrics/segment15_cpace_full_per_subject_hr.csv`,
      `results/metrics/segment15_cpace_full_summary_hr.csv`,
      `results/metrics/segment15_cpace_full_per_subject_plv.csv`,
      `results/metrics/segment15_cpace_full_summary_plv.csv`,
      `results/metrics/segment15_task3_bw_sweep_per_subject_regressions.csv`,
      `results/metrics/segment15_task4_vs_production_per_subject_regressions.csv`,
      `results/figures/segment15_*.png` (3 figures). `README.md` folder-structure
      listing updated.
- [x] **Segment 16 — Android app: HR/PPG stability, SpO2 rigor, UI/UX pass.** **Done
      2026-09-14. Android-only, per the brief — `matlab/` untouched.** Three
      independent tracks, evaluated separately. **Started with no physical device**
      (the local Pixel_7 AVD emulator was tried and never finished booting, 20+
      minutes, `adb devices` stayed `offline` the whole time despite the emulator's
      own hardware-acceleration checks all passing) — **but a real device (the same
      Galaxy A35, `RFCXC0FFFSN`, used throughout this project) became available
      partway through the session, and most of the work below is real-device-
      verified, not just built/unit-tested.** **Task 1**: built
      `signal/DisplaySmoother.kt`, display-level-ONLY rolling-median/EMA smoothing
      of the already-computed, already-CHROM/POS-switched bpm value — explicitly
      NOT a re-implementation of RAKF/Kalman smoothing (`matlab/docs/
      Segment6_Task5_RAKF_Kalman_Smoothing.md` already found that the worst of six
      methods on real data). Unit tests (6/6, later 8/8) caught a null-handling bug
      before any device work. **Real on-device A/B capture (83 distinct recomputes,
      ~66s)**: rolling-median smoothing cut mean tick-to-tick HR jitter from
      17.46bpm to 5.49bpm (**−69%**) and stdev from 24.63 to 20.54, at zero accuracy
      cost. **A second real bug was found via that same capture and fixed before
      trusting the result**: `MainActivity`'s UI ticks 5× faster than the pipeline
      recomputes, so the same raw value was entering the "5-tick" median window up
      to 5× — a window that barely spanned one real measurement, not five. Fixed by
      de-duplicating consecutive identical inputs inside `DisplaySmoother`; 2 new
      unit tests added (8/8 passing). **Promoted `ENABLE_HR_DISPLAY_SMOOTHING_
      DEFAULT` to `true`** on this real, if single-session/single-subject, evidence.
      Also derived the DSP theory the brief's fps/window-length question needed:
      FFT bin resolution is `1/(window duration)`, independent of sampling rate —
      the frame-skip optimization's fps gain does NOT by itself sharpen resolution;
      it helps via per-window sample averaging and Nyquist margin instead.
      `SignalBuffer.WINDOW_DURATION_SECONDS` left at 25.0 (that specific re-test was
      not run this session — device time went to the smoothing test/bug instead).
      **Task 2**: confirmed at the CODE level AND, once the device arrived, freshly
      on real hardware — SpO2 chip visibly live (`96.81%` alongside `HR: 130bpm`),
      `logcat` showing real R/SpO2 co-movement, zero crashes. Literature search
      (2023+, RGB/webcam PPG SpO2 specifically, VERIFIED-FULL/VERIFIED-INDEX/
      BLOCKED discipline, ~10 sources) found no independently-validated calibration
      this segment could responsibly adopt: the strongest lead (perfusion-guided
      calibration, arXiv:2607.08001) trains coefficients on a different modality
      (wrist IR/red contact PPG) that don't transfer, and this segment's own scope
      (no `matlab/` changes, no reference oximeter) rules out refitting a new one
      honestly — **no calibration change made, said so plainly rather than forcing
      one**. Added (zero-risk, additive): per-channel perfusion index now exposed/
      logged from `LiveSpo2Estimator`'s own existing AC/DC terms — real values now
      on record for the first time (0.007-0.038 observed this session, still too
      few for a defensible graded threshold) — and its existing degenerate-signal
      guard is now a named `LOW_SIGNAL_QUALITY` status instead of a silent log line.
      **Task 3**: `activity_main.xml` redesigned into a rounded "vitals card"
      (larger/bolder values, small captions, per-metric colored status pill driven
      by the new shared `signal.EstimatorStatus` enum plus a UI-only `NO_FACE` case)
      and a debounced "No face detected" banner — directly answering the brief's
      "no face detected"/"low confidence"/"warming up" states request, which the
      prior layout collapsed into one undifferentiated placeholder. New `colors.xml`
      extracted from colors already used inline in `OverlayView.kt`/
      `SignalChartView.kt`. Presentation-only — no camera/signal/calibration code
      touched. One real XML build failure hit and fixed (`--` inside a comment, the
      same pitfall this project's own Android README already documented once
      before) — hit AGAIN later in the same task while fixing the text-wrap bug
      below, same fix applied. **Real before/after captures verified on-device**
      (git-stashed this task's changes to rebuild the genuine pre-redesign layout
      for the "before" shot): flat 20sp text/no status feedback → rounded card with
      color-coded pills, captured live/warming-up/no-face. **A real bug found via
      the first capture**: the value text wrapped onto two lines at 34sp bold in
      the card's half-width column — fixed by dropping the redundant "HR:"/"SpO2:"
      prefix (the caption already says "HEART RATE"/"BLOOD OXYGEN"), re-verified on
      a second capture. **No screenshot files retained** — deleted at the user's
      request after verification (2026-09-14); confirmed never committed to git and
      never pushed to GitHub (all were untracked local files at deletion time). Full
      detail: `android/docs/Segment16_Task1_HR_Stability.md`,
      `Segment16_Task2_SpO2_Research_and_Audit.md`, `Segment16_Task3_UI_UX_Pass.md`
      (all three updated with real on-device results, not just the original
      no-device plan).
      Outputs: `android/app/src/main/java/com/spandan/app/signal/DisplaySmoother.kt`,
      `EstimatorStatus.kt`, `app/src/test/.../DisplaySmootherTest.kt`,
      `res/values/colors.xml`, `res/drawable/bg_vitals_card.xml`,
      `bg_status_pill.xml`, `bg_no_face_banner.xml`, `shape_status_dot.xml`.
      Modified (additive only, numeric logic unchanged):
      `signal/RealHeartRateEstimator.kt`, `signal/LiveSpo2Estimator.kt`,
      `MainActivity.kt`, `res/layout/activity_main.xml`, `res/values/strings.xml`,
      `android/README.md`.
- [x] **Segment 17 — `run_spandan_interactive.m`: stop duplicating the pipeline, call
      the current one.** **Done 2026-09-14.** Abrar asked for one MATLAB file that runs
      the whole current pipeline and can select the subject video from anywhere on the
      computer, and asked to update the existing file if one already existed —
      `scripts/run_spandan_interactive.m` already had the `uigetfile`-any-video part,
      but per its own header it deliberately ran a frozen, standalone, verbatim-copied
      snapshot of the pipeline from Segment 7/8, explicitly NOT
      `pipeline/estimateVitalsAndMorphology.m` off the path — so Segments 10-16
      (confidence gate now default `true`, cPACE, mid-band, the Gaussian filter) were
      silently absent from it. Deleted ~1200 lines of duplicated pipeline functions;
      added a self-locating path bootstrap (`mfilename('fullpath')` →
      `addpath(genpath('../src'))`) at the top so the file now calls the real,
      current `matlab/src/` functions — the same ones every batch script here uses —
      and will never go stale again by construction. **Flagged, not silently dropped**:
      the old file's `chooseHeuristicPolarityByNotchConfidence` (a real, evidence-based
      polarity-selection improvement for Cases 2/3, no ground truth) was never ported
      into `matlab/src/morphology/fixPolarity.m`, so it's gone from this file too —
      Cases 2/3 now use the same plain skewness heuristic production/Android already
      use, which is the more honest "current pipeline" answer but leaves the
      skewness-rule bias `fixPolarity.m`'s own header already documents unaddressed. A
      real follow-up, not done here: port that confidence-anchored logic into
      `fixPolarity.m` itself, or add it as an `opts.polarityMethod` hook on
      `estimateVitalsAndMorphology.m`. All function-signature call sites checked
      argument-for-argument against the current `matlab/src/**.m` files (not assumed
      compatible); the rewritten file structurally verified (every block/`end` pairs)
      but **not executed in MATLAB this session** (no MATLAB in this environment) —
      Abrar should run it once to confirm before a live demo. See the Current State
      entry above for the full rationale. Output: `matlab/scripts/run_spandan_interactive.m`
      (rewritten, same filename/entry point).
- [x] **Segment 18 — Android camera throughput + buffer-window revisit (Workstream 1).**
      **Done 2026-09-15/16, real on-device measurement, Samsung Galaxy A35
      (`RFCXC0FFFSN`), same device used throughout this project.** First re-synced
      `ProfilingFaceAnalyzer.kt` against `FaceAnalyzer.kt`'s current N=3 detection-skip
      logic per this task's own instruction — **found already in sync this time** (not
      stale, unlike the two prior occasions this project's history records). Profiled the
      current ~19-20fps path: ML Kit detection remains ~98% of per-frame cost
      (73-81ms/detect-frame observed this session), ROI/pixel-averaging negligible
      (<5ms) — confirms Segment 7 Task G's finding still holds, no new bottleneck shifted
      into view. **New, gated (`useMotionTracking`, default `false`) real inter-detection
      tracker** replacing "freeze the last box" on skipped frames: `camera/
      OpticalFlowMatcher.kt` (pure SAD block-match on a downsampled luma patch, no
      Android dependency, unit-tested against synthetic shifted patches) +
      `camera/OpticalFlowFaceTracker.kt` (Android wrapper, samples the Y-plane, tracks in
      SENSOR space) + a new `CoordinateMapper.sensorRectToRotatedRect` (the mathematical
      inverse of the existing `rotatedRectToSensorRect`, verified via a random-rect
      round-trip test, since no device was available yet when it was written).
      Deliberately NOT a KLT/optical-flow-library tracker — `matlab/docs/
      Segment7_Task_D_Landmark_ROI.md`'s own finding (a KLT-tracked ROI net-regressing
      MATLAB accuracy) was cited as a reason to keep this simpler.
      **Real re-measurement, three back-to-back captures on the same device/session**:
      baseline (no tracking) 19.96fps steady-state (40s window, 66.7% skip fraction,
      matching the ideal N=3 ratio); with tracking enabled, **16.33fps — SLOWER**, despite
      the tracker's own self-reported cost being negligible (mean 0.874ms/skipped frame,
      max 7.35ms). A same-session baseline re-check (to isolate thermal/session drift)
      found detection latency itself had ALSO risen to match the tracking capture's level
      (80.86ms vs the tracking capture's 80.08ms) yet still held **19.19fps** — ruling out
      simple thermal drift as the full explanation for the tracking capture's slower
      16.33fps. **Verdict: NOT adopted — kept off by default (already the default), a
      real, unrounded-up negative result**: the tracker's own measured cost is negligible
      but end-to-end throughput regressed ~15-18% for a reason not fully isolated this
      session (leading, unproven hypothesis: per-skipped-frame `IntArray` allocation/GC
      pressure not visible inside the tracker's own `SystemClock` timing window) — flagged
      as a follow-up needing real heap/allocation profiling tools this session didn't
      have, not silently blamed on "probably thermal" without the controlling re-check
      that argues against it. **Task 4 (buffer window)**: `SignalBuffer.
      WINDOW_DURATION_SECONDS` **kept at 25.0s** — this session's real measured baseline
      fps (19.19-19.96) sits close to the previously documented 21.40fps (real
      device/session variance, same order of magnitude, same N=3 mechanism), so nothing
      changes Segment 16's existing accuracy-vs-responsiveness tradeoff analysis. Real
      interaction with Segment 19 noted and since CONFIRMED live (see that entry): live
      fs varied 14.16-22.08Hz during actual on-device use this session, making Branch 2's
      wide/mid band-mode fallback a genuinely exercised code path, not a theoretical
      concern. **Task 5 (GC jitter) explicitly NOT re-investigated**, per this task's own
      instruction that it was already closed. Full detail:
      `android/docs/Segment18_Camera_Throughput_And_Buffer_Window.md`. New:
      `camera/OpticalFlowMatcher.kt`, `camera/OpticalFlowFaceTracker.kt`,
      `app/src/test/.../camera/OpticalFlowMatcherTest.kt`,
      `app/src/test/.../camera/CoordinateMapperTest.kt`. Modified (additive):
      `camera/CoordinateMapper.kt` (new `sensorRectToRotatedRect`), `camera/
      FaceAnalyzer.kt` (new `useMotionTracking` param, default `false`, byte-identical
      behavior when off), `camera/ProfilingFaceAnalyzer.kt` (mirrored, plus a new
      `motionMs` profiling phase).
- [x] **Segment 19 — port Branch 2 (waveform morphology/dicrotic notch) to Android
      (Workstream 2).** **Done 2026-09-15/16, real on-device verification, same Galaxy
      A35.** Read `matlab/src/pipeline/estimateVitalsAndMorphology.m`,
      `morphology/{bandpassMorphology,adaptiveHarmonicFilter,notchDetectIEM,
      harmonicSelectiveGaussianFilter,harmonicFilterConfidenceGate,
      extractMorphologyWaveform,ensembleAverageBeats,fixPolarity,resampleUniform}.m`
      directly from source before writing any Kotlin, per this task's own instruction.
      **New Kotlin ports** (all under `signal/`, parallel to Branch 1, never merged into
      it): `PchipInterpolator.kt` (a new SHARED Fritsch-Carlson PCHIP utility — MATLAB has
      no single file for this, it's inlined via `interp1(...,'pchip')` in three different
      functions; consolidating it into one Kotlin file is a deliberate, stated structural
      difference from the MATLAB source, not a missed file), `MorphologyBandpassFilter.kt`
      (wide/mid, reuses `BandpassFilter`'s own already-public design/filtfilt code rather
      than duplicating it; adds a `pick(fs)` fallback the MATLAB side never needed since
      its batch clips are always well above 16fps), `AdaptiveHarmonicFilter.kt` (ABPF comb
      via JTransforms complex FFT/IFFT), `HarmonicSelectiveGaussianFilter.kt`,
      `HarmonicFilterConfidenceGate.kt` (the safe single-fallback mode ONLY — the MATLAB
      source's own discouraged multi-candidate mode is deliberately not ported, flagged in
      this file's own KDoc so a future caller doesn't reach for it blind), `FixPolarity.kt`
      (heuristic only — `fixPolarityByGroundTruth.m`/`estimateLagPolarityByGroundTruth.m`
      excluded per the brief, since Android never has a contact-PPG reference),
      `ResampleUniform.kt`, `EnsembleAverageBeats.kt`, `NotchDetectIEM.kt` (Savitzky-Golay
      edge handling deviates from MATLAB's exact `sgolayfilt` boundary convention, stated
      explicitly, same discipline as `WaveletDenoise.kt`'s own boundary note), and the
      orchestrator `MorphologyWaveformEstimator.kt` (mirrors `estimateVitalsAndMorphology.m`'s
      Branch 2 sequence exactly, `useConfidenceGate` default `true` matching production;
      reuses the EXISTING `EstimatorStatus` enum per this task's own instruction rather than
      inventing a new convention; wraps `EnsembleAverageBeats`/`FixPolarity`'s MATLAB-faithful
      hard errors in a fail-soft catch, a deliberate, stated divergence for live camera data).
      **UI**: new `ui/WaveformView.kt` (Canvas draw of the ensemble-averaged beat + a notch
      marker) plus a "WAVEFORM MORPHOLOGY (BRANCH 2)" card in `activity_main.xml`, matching
      the existing vitals-card style exactly; the status pill surfaces the RAW (unclipped)
      notch confidence NUMBER and which filter was used, not just a pass/fail — colored by
      `EstimatorStatus` plus (when `OK`) a second check against the 0.3 confidence bar,
      since `OK` alone only means "a value was computed," not "a confident one." **49/49
      unit tests pass** (10 new signal test files + `MorphologyWaveformEstimatorTest`'s
      end-to-end orchestration sweep across a realistic fps range, plus every pre-existing
      test), all synthetic-signal-verified before trusting real camera data, same
      discipline as every numeric port in this project. **Real on-device verification**: 9
      successful Branch 2 recomputes captured over a ~40s continuous face-in-frame window,
      **zero exceptions, zero crashes, app pid stable throughout**. Real MID-band fallback
      fired at a real measured fs=14.33Hz (Nyquist=7.17Hz < WIDE's 8Hz cutoff, correctly
      inadmissible; MID's 6Hz cutoff fits) with ABPF passing at notch confidence 0.818; real
      WIDE band fired at fs≥21.4Hz; the confidence gate substituted to Gaussian(0.15) in 6/9
      windows (ABPF failed the 0.3 bar) and stayed on ABPF in 3/9 — BOTH paths genuinely
      exercised on real data, not just unit-tested; notch confidence spread 0.019-0.869
      across windows, matching this project's own MATLAB-side documented wide variance
      (Segment 10 Task 1's pooled result), not a bug. **Branch 1 confirmed unaffected** on
      the same capture — `RealHeartRateEstimator`/`LiveSpo2Estimator` logged normally
      throughout (HR 51-136bpm, consistent with this project's already-documented jitter
      pattern; SpO2 ~96.8-97.1%), no shared state, no new exceptions. A screenshot (not
      retained, per this project's own established no-screenshot-retention practice)
      confirmed the card renders correctly and — a genuinely useful real-data catch — that
      the status pill correctly showed "Low signal quality" on one tick while HR/SpO2
      simultaneously showed "Live"/OK, confirming Branch 1/Branch 2 independence end to
      end, not just by code inspection. **Real fs this ran at, stated per the task's own
      instruction: 14.16-22.08Hz** (live, varying). **Ambiguities flagged, not silently
      guessed**: (1) `NotchDetectIEM`'s Savitzky-Golay boundary handling (see above); (2)
      no MATLAB precedent exists for the confidence gate's fallback candidate itself
      failing (a live-camera-only failure mode) — resolved by keeping the primary (ABPF)
      result rather than inventing a third path; (3) `trimmean`'s exact trim-count rounding
      isn't verified bit-exact against MATLAB's own tie-breaking; (4) the 2000ms recompute
      interval / 10s minimum window are this port's own choice, confirmed only to keep up
      without a backlog on the one real capture taken, not tuned against a full on-device
      CPU budget. Full detail: `android/docs/Segment19_Branch2_Morphology_Port.md`. New:
      `signal/{PchipInterpolator,MorphologyBandpassFilter,AdaptiveHarmonicFilter,
      HarmonicSelectiveGaussianFilter,HarmonicFilterConfidenceGate,FixPolarity,
      ResampleUniform,EnsembleAverageBeats,NotchDetectIEM,MorphologyWaveformEstimator}.kt`,
      `ui/WaveformView.kt`, 10 new test files under `app/src/test/.../signal/`. Modified
      (additive only): `MainActivity.kt`, `activity_main.xml`, `strings.xml`,
      `app/build.gradle.kts` (`testOptions.unitTests.isReturnDefaultValues=true` — a
      standard, safe Android unit-test config needed because `Log.d`/`.w` throws "not
      mocked" under plain JUnit; no production behavior change).
- [x] **Segment 18 (MATLAB colour-space; number collides with the Android Segment 18
      above, files are named `segment18_colorspace_*`) — CIELab a\* / YCbCr Cb, Cr as
      pulse channels vs. green.** **Done 2026-09-20. NOT promoted.** Diagnostic only;
      `estimateVitalsAndMorphology.m`, CHROM, POS untouched. New
      `roi/extractROISignalsLab.m` (R/G/B bit-identical to `extractROISignals.m`, verified;
      also returns all four Task N regions per pass). Pool: 5 UBFC + 107 VIPL v1 (N=112,
      fresh green matches the segment4 baseline 112/112) plus a new 20-subject VIPL v2
      (head motion) pool. **Result**: a\* beats green (MAE 14.98→9.53, r 0.09→0.43, sign-rank
      p=0.0001) but still loses to production CHROM/POS (7.83/7.22); Cb ≈ green; Cr
      marginal. a\* has 12 severe (>10 bpm) per-subject regressions, mostly peaks near the
      0.7Hz band edge. Median cross-ROI PLV does NOT favour a\*/Cb/Cr (0.275/0.231/0.271 vs
      green 0.310); v2 motion pool: a\* 14.51 vs green 21.81 bpm, PLV differences ~0.01-0.02.
      **Limitation stated in the doc**: the main pool has no deliberate head motion, so
      this cannot validate the motion-robustness claim; v2 (N=20) is weak evidence.
      Full detail: `matlab/docs/Segment18_ColorSpace_Ablation.md`. Outputs:
      `matlab/src/roi/extractROISignalsLab.m`,
      `matlab/scripts/run_segment18_colorspace_{ablation_batch,ablation_motion_batch,evaluation}.m`,
      `results/metrics/segment18_colorspace_{ablation,ablation_motion,pooled_metrics,
      pooled_metrics_motion,per_subject_vs_green,per_subject_vs_green_motion}.csv`.

---

## Completed Work (Archive)

All 7 items below are done and verified — kept here per this file's own Maintenance
Protocol (never silently delete a status line). Full instructions/context for each are
in the master handoff conversation that produced them; if that isn't available, the
summary below plus the referenced docs/papers should be enough to reconstruct the
intent. Nothing here needs re-running unless you have a specific reason to doubt a
result — verify against the named output files first.

- [x] **Action 1 — Fix Task J.** ~~Diagnose the empty-output bug...~~ **Done 2026-09-12.**
      Cause was a py.* per-landmark round-trip leak, not the suspected pyenv session
      conflict — fixed by batching into one Python-side list comprehension per frame.
      Result: hybrid ROI is net-negative (1/5, below baseline's 4/5 and KLT's 2/5). See
      Current State above and `docs/Segment7_Task_J_FaceMesh_Hybrid_ROI.md` for full
      detail. Outputs: `results/metrics/segment7_task_j_facemesh_hybrid_notch.csv`,
      `results/metrics/segment7_task_j_facemesh_hybrid_branch1_hr.csv` (both verified
      against the doc — real rows, not headers-only). **No further action needed on
      Task J itself** — this line of ROI experimentation (baseline vs. KLT vs. real
      mesh vs. hybrid) is closed; the axis-aligned box stays production.
- [x] **Action 2 — Template-collapse diagnostic.** **Done 2026-09-13.** Confirmed GT
      *waveform* (not just scalar HR) exists far beyond the assumed 5: UBFC-D1 (5),
      UBFC-D2 (42, not run — disk space), VIPL (95 of 107, v1/source1). Ran the full
      rPPG-vs-GT ensemble-prototype chain on 100 subjects (UBFC-D1 5 + VIPL 95), 0
      failures. **Result: no support for template collapse** — rPPG cross-subject mean
      correlation (0.9300) is actually LOWER than ground truth's (0.9719), the opposite
      of what collapse would predict; GT is near-uniformly self-similar (100% of pairs
      ≥0.85) which is a known property of real PPG shape, not a defect. Caveat: whole-
      cycle Pearson is a coarse metric dominated by the systolic peak, doesn't rule out
      notch-region-specific templating — see the doc for the honest limitation. No
      retraction of Task B's 4/5 result warranted. Full writeup:
      `docs/Segment7_Task_K_Template_Collapse_Diagnostic.md`. Outputs:
      `results/metrics/segment7_task_k_template_collapse_summary.csv`,
      `results/metrics/segment7_task_k_correlation_summary.csv`,
      `data/processed/segment7_task_k_prototypes.mat`,
      `data/processed/segment7_task_k_correlation_matrices.mat`.
- [x] **Action 3 — Real timing-correction fix.** **Done 2026-09-13.** Key finding
      established first: source2 has no `time.txt` (confirmed), so there are no real
      per-frame timestamps to cubic-spline-resample FROM — Chen/Lin/Jeong's method needs
      real jitter data it structurally doesn't have here. Tested anyway (empirically, not
      just argued): spline-interpolating through fictional container-rate labels gives
      pooled MAE 18.74bpm — barely better than the uncorrected baseline (19.41bpm) and
      much worse than the already-adopted relabel fix (13.83bpm). **Verdict: cubic-spline
      does NOT beat relabel for source2 — keep the relabel fix, don't replace it.**
      Separately investigated why p84/p100/p104/p107 regress under relabel: checked both
      suggested culprits (source3's own frame jitter, source2-vs-source3 duration
      mismatch) directly against all 12 subjects — **neither explains the pattern**
      (p104 has the CLEANEST source3 timing of all 12 yet is one of the 4 that regress;
      p105 has the LARGEST duration mismatch of all 12 yet improved). Best-supported
      explanation: source2's own uncorrectable per-frame capture jitter, not the borrowed
      sibling-duration estimate — inference, not proven (no independent source2 timing
      data exists to check directly). New reusable file
      `filtering/resampleSource2CubicSpline.m` (general, not source2-specific — ready for
      a future source1/3/4 investigation, which DO have real `time.txt`). Full writeup:
      `docs/Segment8_Task3_Source2_Timing_Fix.md`. Output:
      `results/metrics/segment8_task3_source2_timing_comparison.csv`.
- [x] **Action 4 — DWT wavelet-shrinkage denoising.** **Done 2026-09-13.** New
      `filtering/waveletDenoise.m` (db4, 3-level, Donoho-Johnstone universal
      soft-threshold), additive pre-step, ablated on the full 112-subject pool (112/112
      succeeded, 0 failures). **Result: net improvement on every metric, both combiners**
      — CHROM MAE 9.10→7.83bpm, RMSE 18.00→11.87bpm, r 0.31→0.53; POS MAE 8.68→7.22bpm,
      RMSE 16.45→10.85bpm, r 0.28→0.62. Not uniform though: 39/112 subjects changed at
      all, and while most improved (e.g. p48: error 42.1→12.3bpm), 7 regressed by
      >10bpm on CHROM (worst: p85, 0.4→45.8bpm). Confirmed the "no harmonic-lock risk"
      expectation at the pool level (RMSE improved, the opposite of what a systematic
      lock mechanism would do) — p85's regression is a real but different, occasional
      failure mode (no f0 dependency in the method, unlike ABPF). Full writeup:
      `docs/Segment8_Task4_Wavelet_Denoise_Ablation.md`. Output:
      `results/metrics/segment8_task4_wavelet_ablation.csv`.
      ~~**Adopt as an available additive option for Branch 1**~~ **[2026-09-13]
      PROMOTED TO DEFAULT** in both MATLAB and Android — see the new Action 7
      entry below for the full promotion (production numbers regenerated and
      verified, Android port added and build-verified). Kept struck through
      rather than deleted, per this file's own Maintenance Protocol rule 2.
- [x] **Action 5 — Residual-adaptive Kalman smoothing (RAKF).** **Done 2026-09-13.** New
      `validation/residualAdaptiveKalmanHR.m`, head-to-head against Task P/Q on the same
      107-subject pool + cached windows. **Result: RAKF does not win anywhere** — MAE
      12.15/RMSE 22.04/r 0.204, the WORST of all 6 methods compared (whole-clip, naive
      windowed, gating-only, Task P continuity, Task Q anchored continuity, RAKF); also
      worse than whole-clip on the pooled 112 (MAE 11.83 vs. 9.10). The best methods on
      this pool remain the simplest: naive windowing and gating-only both beat every
      continuity/Kalman-based method tried across Tasks P, Q, and 5. Caveat: RAKF's
      R0/beta/Q are this implementation's own data-derived defaults, not verified against
      the paper's own Eq. 9-18 — a parameter sweep might do better, not attempted. Full
      writeup: `docs/Segment6_Task5_RAKF_Kalman_Smoothing.md`. Outputs:
      `results/metrics/segment6_task5_rakf_vipl107_metrics.csv`,
      `results/metrics/segment6_task5_rakf_pooled112_metrics.csv`.
- [x] **Action 6a — Android frame-skip.** ~~**Code done 2026-09-13, re-measurement
      BLOCKED (no device).**~~ **[2026-09-13] CLOSED, real numbers captured.** A
      physical device (Samsung Galaxy A35) was attached this session. `ProfilingFaceAnalyzer.kt`
      was first updated to mirror `FaceAnalyzer.kt`'s frame-skip logic (it had gone
      stale — it was still detecting every frame, which would have re-measured the
      pre-optimization baseline), then temporarily wired into `MainActivity.kt`
      exactly per the doc's own Section 1 capture method, run for a real ~171s capture
      with a face continuously in frame, then reverted (confirmed by a post-revert
      `gradlew assembleDebug` + reinstall). **Real result: 13.44fps -> 21.40fps
      steady-state, a genuine ~1.59x speedup — reported plainly, and plainly short of
      the doc's own naive "3x baseline" (40.3fps) projection**, because detection
      isn't the only cost once it's cheaper, and the app's other concurrent work
      (HR/SpO2 estimation) shares the same device in both captures (an
      apples-to-apples comparison, not a new confound). Full detail:
      `android/docs/Segment7_Task_G_Throughput_Profiling.md`'s own updated section 3.
- [x] **Action 7 — Promote wavelet denoising to default (MATLAB + Android).** **Done
      2026-09-13.** MATLAB: `useWaveletDenoise` toggle (default `true`) added to
      `scripts/run_segment3_filtering_batch.m` and `scripts/run_vipl_integration_batch.m`,
      applying `filtering/waveletDenoise.m` to each raw R/G/B channel immediately before
      `detrendSignal.m`, same position Action 4's ablation used.
      `results/metrics/segment6_hr_pooled_metrics.csv` regenerated (old version preserved
      as `..._prewavelet.csv`) by reusing Action 4's already-computed
      `segment8_task4_wavelet_ablation.csv` CHROM/POS numbers directly (exact same
      computation, so no video reprocessing needed) — new pooled result CHROM MAE
      7.83bpm/RMSE 11.87/r=0.53, POS MAE 7.22bpm/RMSE 10.85/r=0.62, VERIFIED to match
      `docs/Segment8_Task4_Wavelet_Denoise_Ablation.md`'s own pooled table exactly
      (script's own built-in check passed). ~~Green-only HR is UNCHANGED~~ [SUPERSEDED 2026-09-20: this was a splice artifact, never reconciled; see the 2026-09-20 wavelet-orchestrator entry] (Action 4 never
      ablated it — a diagnostic method, not a shipped result — stated explicitly rather
      than silently implied). `docs/Spandan_Final_Pipeline_Report.md`'s Branch 1 section
      updated (strikethrough + replace) to cite this as the new default, caveat kept on
      record. New script: `scripts/run_segment8_action2_promote_wavelet_default.m`.
      Android: new `android/app/src/main/java/com/spandan/app/signal/WaveletDenoise.kt`
      (db4, 3-level, Donoho-Johnstone universal soft-threshold — same math as the MATLAB
      port, periodic instead of symmetric boundary handling, stated explicitly in the
      file's own header, since exact sample-for-sample match wasn't required, only a
      real denoise), wired into `RealHeartRateEstimator.kt` (`useWaveletDenoise` ctor
      param, default `true`) immediately before `BandpassFilter.detrend`. Verified with a
      new JUnit test (`WaveletDenoiseTest.kt`, plain Kotlin/JUnit, no device needed):
      synthetic 1.2Hz sinusoid + Gaussian noise, RMSE-vs-clean 0.3034→0.2683 (a real
      reduction, smaller than MATLAB's own 0.3185→0.1968 due to the boundary-handling
      difference — expected and stated, not hidden). `gradlew assembleDebug` confirmed
      green both before and after this change. Outputs/files touched:
      `results/metrics/segment6_hr_pooled_metrics.csv`,
      `results/metrics/segment6_hr_pooled_metrics_prewavelet.csv`,
      `matlab/scripts/run_segment3_filtering_batch.m`,
      `matlab/scripts/run_vipl_integration_batch.m`,
      `matlab/scripts/run_segment8_action2_promote_wavelet_default.m`,
      `matlab/docs/Spandan_Final_Pipeline_Report.md`,
      `android/app/src/main/java/com/spandan/app/signal/WaveletDenoise.kt`,
      `android/app/src/main/java/com/spandan/app/signal/RealHeartRateEstimator.kt`,
      `android/app/src/test/java/com/spandan/app/signal/WaveletDenoiseTest.kt`.
- [x] **Action 6b — Phase distortion assessment.** **Done 2026-09-13.** Direct code
      read confirms `BandpassFilter.apply()` uses `filtfilt` (genuine zero-phase,
      forward+reverse+forward+reverse-back), NOT causal `lfilter` — Lapitan et al.'s
      concern is inapplicable by construction, not just "doesn't matter at this
      order/cutoff." Quantified what a causal version WOULD have cost: mean group delay
      152.6ms (fs=30) / 152.0ms (fs=25) over the 0.7-4Hz band, up to ~450ms at band
      edges — a real, non-trivial fraction of a cardiac cycle, genuinely avoided by the
      zero-phase design. Full writeup:
      `android/docs/Segment7_Task_H_Phase_Distortion_Assessment.md`.

**Do not touch** (already validated, regression risk only): `pulseextraction/chromCombine.m`,
`pulseextraction/posCombine.m`, `heartrate/fftHeartRate.m`, `morphology/adaptiveHarmonicFilter.m`'s
existing behavior, `filtering/waveletDenoise.m`'s internals (now a production default, not
just an ablation — its math is verified, only its call sites should ever change),
`morphology/harmonicFilterConfidenceGate.m`'s own gating logic (now a production default as
of Segment 14 Task 2 — its 0.3-bar/ABPF-primary/Gaussian-0.15-fallback design is settled and
validated on 133 held-out+audit-pool subjects; re-tune only with a new, explicit ablation,
same discipline as everything else in this project), `android/.../signal/WaveletDenoise.kt`'s
internals (same reason), `FaceAnalyzer.kt`'s frame-skip logic (measured and adopted, not a
draft), `BandpassFilter.kt`'s `filtfilt` implementation (confirmed zero-phase/correct),
anything marked done in `android/docs/Defense_Readiness_Checklist.md` — except where an
action above explicitly adds an alternative alongside it.

---

## Changelog

*(Append one entry per session, oldest first. Don't rewrite past entries — see
Maintenance Protocol rule 3.)*

- **2026-09-12** — File created (Claude, Cowork session), seeded from a planning
  conversation covering face-mesh ROI experiments (Tasks H/I/J), a literature review
  (5 papers verified), and the Segment 8 source2 FPS finding. No code changed by this
  entry — this is the initial snapshot only.
- **2026-09-12** — Action 1 (Task J) completed and verified. Real bug found (py.*
  per-landmark round-trip leak, not the pyenv-session-conflict guess) and fixed by
  batching landmark reads into one Python-side list comprehension per frame; both
  batches then ran clean. Result verified directly against
  `results/metrics/segment7_task_j_facemesh_hybrid_notch.csv`,
  `..._branch1_hr.csv`, and `docs/Segment7_Task_J_FaceMesh_Hybrid_ROI.md` — numbers
  match across all three. Verdict: hybrid ROI is a partial confirmation of Task H's
  pixel-count hypothesis but still net-negative (1/5 vs. baseline's 4/5); no ROI
  variant tried so far beats the simple axis-aligned box. This closes the
  baseline/KLT/mesh/hybrid ROI line of investigation for the notch metric. Remaining
  queue: Actions 2-6 (see above), still pending.
- **2026-09-13** — Action 2 (template-collapse diagnostic) completed. Confirmed GT PPG
  *waveform* data exists for far more than the assumed 5 subjects (UBFC-D2 42, VIPL 95
  more) — see doc. Ran the full ensemble-prototype chain on 100 subjects (UBFC-D1 5 +
  VIPL v1/source1 95; UBFC-D2 skipped, disk space — a UBFC DATASET_2 extraction attempt
  briefly filled H: to 0 bytes, rolled back cleanly with no data loss, then
  `VIPL-HR-V1`'s redundant raw archive was relocated to I: instead to free room — see
  Current State's disk-housekeeping note). Result: cross-subject correlation is LOWER
  for rPPG (0.93) than ground truth (0.97) — no support for template collapse, opposite
  of the concern. Full detail, caveats, and the exact numbers:
  `docs/Segment7_Task_K_Template_Collapse_Diagnostic.md`. Remaining queue: Actions 3-6.
- **2026-09-13** — Action 3 (source2 timing fix) completed. Established source2 has no
  real per-frame timestamps to cubic-spline from (no `time.txt`); tested anyway
  (fictional-label spline) and confirmed empirically it does NOT beat the already-adopted
  relabel fix (pooled MAE 18.74bpm vs. relabel's 13.83bpm, barely better than no
  correction's 19.41bpm) — relabel stays adopted. Investigated why
  p84/p100/p104/p107 regress under relabel: neither suggested culprit (source3 jitter,
  duration mismatch) explains the pattern when checked against all 12 subjects; best
  supported explanation is source2's own uncorrectable per-frame jitter, stated as
  inference not proof. Full detail: `docs/Segment8_Task3_Source2_Timing_Fix.md`.
  Remaining queue: Actions 4-6.
- **2026-09-13** (same session, continued) — Action 4 (DWT wavelet-shrinkage) and Action
  5 (RAKF) both completed. Action 4: genuine pooled improvement on the full 112-subject
  pool, both CHROM and POS, every metric (RMSE drop of ~6bpm) — but not uniform, 7
  subjects regress >10bpm even as the pool improves; full detail
  `docs/Segment8_Task4_Wavelet_Denoise_Ablation.md`. Action 5: RAKF does NOT beat any of
  Task P/Q's existing methods or the plain whole-clip baseline, on either the 107-VIPL
  head-to-head or the pooled 112 — the simplest methods (naive windowing, gating-only)
  remain the best performers found across Tasks P/Q/5 combined; full detail
  `docs/Segment6_Task5_RAKF_Kalman_Smoothing.md`. **Also note**: mid-session, MATLAB
  batch launches started getting killed instantly by the harness citing low system
  memory (5.1GB free physical RAM at the time, no orphaned processes found) — the
  wavelet-ablation batch was interrupted twice this way before completing on a third
  attempt; its script now has resume-skip logic (checks the output CSV for already-done
  subjectIDs before reprocessing) in case this recurs for a future session — see the
  script's own comments. Remaining queue: Action 6 (Android, a/b).
- **2026-09-13** (same session, continued) — Action 6 (Android). 6b (phase distortion)
  fully done: `BandpassFilter.kt` confirmed zero-phase (`filtfilt`, not causal) by direct
  code read, Lapitan et al.'s concern doesn't apply here by construction; quantified the
  causal-filter delay this design avoids (~152ms mean, ~450ms at band edges) for a
  concrete number rather than just asserting it. See
  `android/docs/Segment7_Task_H_Phase_Distortion_Assessment.md`. 6a (frame-skip) code
  done and build-verified (`FaceAnalyzer.kt`, N=3 detection skip + last-box reuse,
  `gradlew assembleDebug` succeeds) but the real on-device re-measurement is BLOCKED —
  no physical device was attached this session. This is the one open item left in the
  original 6-action queue: connect a device, temporarily wire `ProfilingFaceAnalyzer`
  into `MainActivity.kt` per `android/docs/Segment7_Task_G_Throughput_Profiling.md`'s own
  capture method, measure, revert. **All 6 actions from the original handoff have now
  been addressed** (5 fully closed, Action 6a's code done with its measurement pending
  hardware) — see each action's own entry above for the real numbers.
- **2026-09-13** (new session) — Two things closed. **(1) Wavelet denoising promoted to
  default, both MATLAB and Android** (new Action 7 above): MATLAB's
  `run_segment3_filtering_batch.m`/`run_vipl_integration_batch.m` now apply
  `waveletDenoise.m` by default (`useWaveletDenoise=true` toggle);
  `segment6_hr_pooled_metrics.csv` regenerated and verified to match
  `docs/Segment8_Task4_Wavelet_Denoise_Ablation.md`'s pooled table exactly (CHROM MAE
  7.83/RMSE 11.87/r=0.53, POS MAE 7.22/RMSE 10.85/r=0.62), old numbers preserved as
  `segment6_hr_pooled_metrics_prewavelet.csv`; `docs/Spandan_Final_Pipeline_Report.md`
  updated (strikethrough + replace). New `android/.../signal/WaveletDenoise.kt` (same
  db4/Donoho-Johnstone math, periodic instead of symmetric boundary handling, stated
  explicitly) wired into `RealHeartRateEstimator.kt` ahead of `BandpassFilter`; verified
  with a new JUnit test showing a real RMSE-vs-clean reduction (0.3034→0.2683) and a
  passing `gradlew assembleDebug`. **(2) Action 6a (Android frame-skip re-measurement)
  closed with real numbers** — a physical device (Galaxy A35) was attached this session.
  `ProfilingFaceAnalyzer.kt` needed updating first (it had gone stale, still detecting
  every frame) to actually mirror `FaceAnalyzer.kt`'s frame-skip logic before it could
  measure the optimized path; then the doc's own Section 1 capture method (temporary
  `MainActivity.kt` swap, ~171s live capture with a face in frame, revert) gave a real
  **13.44fps → 21.40fps steady-state** result — a genuine ~1.6x speedup, reported
  plainly as short of the doc's own naive "3x" projection rather than rounded up. Full
  detail in each action's own entry above and in
  `android/docs/Segment7_Task_G_Throughput_Profiling.md`'s updated section 3. **Every
  item in this file's Active Work Queue is now closed.**
- **2026-09-13** (same day, cleanup pass) — Reorganized this file for a clean handoff to
  the next session, per the user's request to make the repo "properly ready to start a
  new session." No code changed. Three things done: **(1)** Moved all 7 completed
  actions from "Active Work Queue" into a new "Completed Work (Archive)" section
  (content unchanged, just relabeled — nothing deleted, per Maintenance Protocol rule
  2), and added a genuinely empty "Active Work Queue" section above it so a fresh
  session sees at a glance that nothing is pending rather than scrolling through 7
  checked boxes to find that out. **(2)** Fixed two Current State bullets that had gone
  stale relative to today's actual work: the Segment 8 source2 FPS bullet still said
  "Not resolved" after Action 3 had already closed it (relabel adopted, cubic-spline
  tested and rejected); the literature bullet still said "NOT yet tried" for DWT
  denoising, RAKF, the timing-correction paper, and the phase-distortion paper, all of
  which were resolved earlier today (Actions 2-6b). Both fixed with strikethrough +
  replace, not silent deletion. **(3)** Extended the "Do not touch" list to cover the
  newly-promoted production code (`waveletDenoise.m`/`WaveletDenoise.kt` internals,
  `FaceAnalyzer.kt`'s frame-skip logic, `BandpassFilter.kt`'s `filtfilt`) so a future
  session doesn't second-guess code that's already validated. **Net result: this file
  now accurately describes a fully-closed queue and a live production pipeline with no
  open threads** — the next session can start genuinely fresh, either picking a new
  research direction or being told one.
- **2026-09-13** (same day) — Made the VIPL data-location fact more discoverable: the
  Current State bullet about the `VIPL-HR-V1` archive move (`H:\...` → `I:\EEE 3-1\EEE
  312\project\dataset\VIPL-HR-V1\`) was previously framed only as a disk-space
  housekeeping note, easy to skip past. Reworded (no facts changed) so it reads as a
  data-availability pointer: if a future task needs more or different VIPL subjects
  than what's already extracted into `spandan/data/raw/VIPL-HR/`, check
  `I:\EEE 3-1\EEE 312\project` first. No code changed.
- **2026-09-13** (new session) — Three exploratory pilots from the Spandan Field Guide's
  "still open" list, all deliberately small-sample, none adopted. **(1)** Android
  multi-region ROI feasibility: a debug-only, never-live-wired
  `MultiRegionProfilingFaceAnalyzer` measured a real ~0.6% fps cost (13.43→13.35
  steady-state) for adding a second cheek ROI pass on the Galaxy A35 — negligible,
  verdict PROMISING for a future bigger port. **(2)** RAKF parameter sweep: fetched
  Debnath & Kim's actual paper for the first time (previously "not independently
  available"), found real R0/Q values AND a genuine formula mismatch (paper uses an
  exponent, this port uses division — flagged, not fixed) — swept 48 combos on 10
  cached VIPL subjects, best combo only modestly improves (MAE 5.22→4.80) and in a
  direction that confirms rather than overturns the original "simpler wins" verdict;
  overall verdict NO. **(3)** New weighted region-switching rule
  (`computeRegionSwitchingEstimateWeighted.m`, standout-check-first then a
  forehead/cheek-weighted vote), tested on Task N's v2/v5 scenarios only — along the
  way found and reported (not fixed) a real discrepancy between Task N's doc-cited
  switcher MAE and a fresh recomputation from the same CSV; net result on the fresh
  numbers is a small real win in v5, flat-to-slightly-worse in v2 — verdict AMBIGUOUS.
  Full detail in each pilot's own doc, named in the Active Work Queue entries above.
  None of the three are scaled beyond their small samples, per the task's own
  instruction; nothing in Current State/production changed as a result.
- **2026-09-13** (same day, planning session) — Queued a new task, Segment 10 Task 1:
  a full rPPG-vs-ground-truth-PPG waveform and frequency fidelity audit, deliberately
  scoped to the FULL 100-subject waveform-GT pool Task K already unlocked (the
  opposite scale direction from the three small pilots above) — time-domain
  (correlation/RMSE/DTW/beat-shape) and frequency-domain (Welch PSD, coherence,
  per-band mismatch energy, harmonic-confusion detection) comparison against real
  ground-truth PPG, not just the scalar HR number every prior comparison used. Not
  started — no code changed, nothing reprocessed. Full scope in the Active Work
  Queue entry above.
- **2026-09-13** (new session) — Segment 10 Task 1 completed: 100/100 subjects (5
  UBFC-D1 + 95 VIPL v1/source1, Task K's exact pool), 0 failures, read-only (no
  "do not touch" file modified; one new additive function,
  `morphology/estimateLagPolarityByGroundTruth.m`). Headline results: pooled
  waveform correlation is modest for all three signals (median r 0.44-0.52); the
  harmonic-comb branch has the best median r but the widest spread and the highest
  harmonic-confusion rate (5/100 vs. 1/100 for CHROM/POS at the primary ±8%
  tolerance) — independent, pool-scale evidence for this project's existing
  decision to keep Branch 1/Branch 2 separate, not a reason to reconsider it. The
  new lag-search method itself is flagged unreliable on 34-46% of subjects
  (worse for harmonic-comb, whose comb construction makes it more alias-prone) —
  the single most load-bearing finding of the audit, and a real methodological
  limitation for any future waveform-alignment work in this project, not just a
  data-quality statement. The detector independently reproduces the known
  VIPL_p21 CHROM harmonic-confusion anecdote exactly (ratio = 2.00). Using this
  project's own 0.3 notch-confidence bar (the boolean `notchDetectIEM.m` output
  is a useless gate at pool scale, 100/100 "detected"), only ~26-28% of this
  VIPL-dominated pool shows a confident GT notch — a new caveat on generalizing
  Task B's 4/5-UBFC notch result beyond UBFC. Full detail, all caveats, and the
  worst-5/best-5 worked examples:
  `docs/Segment10_Task1_Waveform_Fidelity_Audit.md`. Outputs:
  `results/metrics/segment10_waveform_fidelity_per_subject.csv`,
  `..._pooled_summary.csv`, `results/figures/segment10_*.png` (4 figures),
  `scripts/run_segment10_waveform_fidelity_audit.m`,
  `src/morphology/estimateLagPolarityByGroundTruth.m`.
- **2026-09-13** (same day, planning session) — Segment 10 Task 2: a solution
  literature search against Task 1's six findings. No code written, nothing run,
  nothing adopted. New doc `docs/Segment10_Task2_Solution_Literature_Search.md`,
  with every citation explicitly marked VERIFIED-FULL / VERIFIED-INDEX / BLOCKED.
  Headline: arXiv:2606.03802 (the template-collapse paper Task K already checked
  for a DIFFERENT claim) also states a ground-truth waveform-correlation ceiling
  of r≈0.601 and argues the dicrotic notch spans only 1-3 samples at 30fps —
  Task 1's median r of 0.44-0.52 sits just under that, so the doc's first
  recommended action is a zero-new-data ceiling test (existing per-subject notch
  confidence vs. existing per-subject effective fps) to decide whether the
  remaining gap is engineering headroom or a measurement floor, BEFORE
  implementing any candidate fix. Best candidate fix found if it is headroom:
  Harmonic-Selective Gaussian Filtering (Sensors 26(12):3710, 2026), a
  morphology-and-timing-preserving structural alternative to
  `morphology/adaptiveHarmonicFilter.m`'s hard-edged comb. Three papers remain
  BLOCKED (PMC reCAPTCHA) and unread, listed as such in the doc rather than
  silently dropped.
- **2026-09-13** (same day, planning session, revision) — Segment 10 Task 2 doc
  revised to Revision 2 after three previously-BLOCKED papers were retrieved (two
  supplied as PDFs by the user, one via nature.com). No code written, nothing run,
  nothing adopted. The headline changed: Kaur/Lakshminarayanan/Saini, *Missed
  isochromatic cardiac pulsation in rPPG*, Biomed. Opt. Express 17(7):3832 (2026),
  doi:10.1364/BOE.599752, argues this project's underlying rPPG signal model is
  incomplete — a second cardiac-frequency component (isochromatic, along the skin's
  mean-reflectance direction) carries 69-83% of cardiac-band energy, cannot be
  removed by any temporal filter, and mechanistically predicts Task 1 findings (1),
  (4) and (5) plus this project's own long-observed POS>CHROM pattern. Its Stage-1
  fix (project out the normalised per-channel temporal means, P = I - q̂q̂ᵀ) is ~5
  additive lines on quantities Spandan already computes, and is now the
  highest-expected-value candidate on the list. Second finding: pyPPG's explicit
  warning that an 8 Hz ceiling distorts pulse-wave shape (bandpassMorphology.m uses
  0.5-8 Hz), which converges with the ceiling paper's sampling argument on camera
  frame rate as the binding constraint for notch work. Revision 2 also assesses the
  four GitHub toolboxes left unassessed in Revision 1 and ends with a consolidated
  Tier 0-3 candidate list (Tier 0 = four tests that use only data already on disk).
- **2026-09-13** (new session) — Segment 10 Task 3: ran all four Tier 0 diagnostics
  from Task 2's own candidate list, and only that — no Tier 1 work started. New script
  `matlab/scripts/run_segment10_task3_tier0_diagnostics.m` (one file, four sections,
  additive/read-only, confirmed via `git status` that no do-not-touch file changed).
  **Result: 3 of 4 supported, 1 not — and the one that failed was Task 2 Revision 1's
  own headline candidate.** Action 1 (ceiling test) is NOT SUPPORTED: within VIPL's
  real 16-30fps spread (n=95), true fps does not predict notch confidence (r=-0.13 to
  +0.04); the positive-looking pooled correlation is a two-cluster artifact of dataset
  identity (UBFC: constant ~28.7fps + high confidence; VIPL: variable fps + uniformly
  low confidence), not a within-dataset sampling effect — independently re-verified
  Task 1's cached `frameRate` is genuinely `time.txt`-corrected by checking p20's raw
  `time.txt` directly. Action 2 (cross-ROI PLV, Kaur et al.'s ground-truth-free
  fidelity metric) IS supported: r=0.571 (CHROM) / 0.632 (POS) vs. Task 1's own
  GT-referenced correlation, n=20 on Task N's cached region pool — a real candidate
  standing metric. Action 3 (new synthetic two-Gaussian notch waveform, closed-form,
  known ground truth) IS supported: quantifies that `bandpassClean.m`'s narrow
  0.7-4Hz band destroys ~45-50% of notch depth while the already-adopted wide-band
  `bandpassMorphology.m` preserves ~97-100% of it when it can run — but also
  demonstrates directly that at a true 16fps that wide-band filter (and every wider
  order-2 variant tried) is literally inadmissible on Nyquist grounds, a real
  structural gap hitting ~~21%~~ **46% (recount corrected 2026-09-13, see that
  day's own changelog entry)** of Task 1's own VIPL pool. Action 4 (POS cardiac-angle
  measurement, pure measurement, `posCombine.m` untouched) IS supported: measured
  median cardiac angle 109.5° (VIPL 121.4°, UBFC 97.8°) on 25 subjects, landing inside
  Kaur et al.'s own reported 96.6-115.5° range and nowhere near POS's assumed 57° —
  independent, on-Spandan-data corroboration of the isochromatic-contamination
  mechanism. **Net verdict: Tier 1 is worth starting, but for cPACE Stage 1 and
  cross-ROI PLV adoption, not the frame-rate-ceiling framing Task 2 Revision 1 led
  with.** Full detail: `matlab/docs/Segment10_Task3_Tier0_Diagnostics.md`. Outputs:
  `results/metrics/segment10_task3_tier0_action{1,2,3,4}_*.csv`,
  `results/figures/segment10_task3_action{1,2,3,4}_*.png`.
- **2026-09-13** (new session) — Segment 11 Task 1: implemented Kaur et al.'s cPACE
  Stage 1 as a new, gated, off-by-default pre-step (`pulseextraction/cpaceProjection.m`)
  and promoted Task 3's one-off cross-ROI PLV computation into a standing function
  (`validation/computeCrossROIPLV.m`), the two highest-value Tier 1 items from Task 3's
  own verdict; no other Tier 1/2/3 item started. **cPACE result: NOT adopted.** Proven
  algebraically (and verified computationally, exact to machine precision across all 100
  subjects) that Stage 1, wired ahead of Spandan's own `posCombine.m`, is a complete
  no-op for POS — `posCombine.m`'s `S1`/`S2` basis vectors are already exactly orthogonal
  to the projected direction `q_hat`, for any subject, because their raw coefficients
  are zero-sum and normalization is per-subject-adaptive (divide by each channel's own
  mean). For CHROM (whose basis vectors are NOT zero-sum), cPACE genuinely changes the
  signal but makes results modestly worse on this project's 100-subject pool: HR MAE
  7.86→8.72bpm, pooled HR r 0.365→0.275, median waveform correlation 0.445→0.417
  (74/100 subjects regress, one severely). Neither combiner moves in the direction Kaur
  et al.'s own reported cPACE-vs-POS gap would suggest, for a now-understood structural
  reason (their comparison is the full 3-stage cPACE vs. a generic POS, not Stage 1
  alone vs. Spandan's own per-subject-adaptive POS). Per-subject skin-colour angle
  measured for all 100 subjects (median 8.61°) confirms UBFC+VIPL sit squarely in Kaur
  et al.'s "lightly pigmented" range, nowhere near the darker-skin range where their
  reported gains are largest — POS's invariance is skin-tone-independent by proof, but
  CHROM's regression was only measured on this light-skin cohort and might not
  generalize to a future darker-skinned one (e.g. the planned Bangladeshi
  self-collected set). **PLV result: adopted** as a standing, ground-truth-free
  fidelity metric — `README.md`'s folder-structure listing updated so future sessions
  find it without this task's context. Full detail:
  `matlab/docs/Segment11_Task1_cPACE_Stage1_and_PLV_Metric.md`. Outputs:
  `matlab/src/pulseextraction/cpaceProjection.m`,
  `matlab/src/validation/computeCrossROIPLV.m`,
  `matlab/scripts/run_segment11_task1_cpace_and_plv.m`,
  `results/metrics/segment11_cpace_before_after.csv`,
  `results/metrics/segment11_cpace_skin_angle_per_subject.csv`,
  `results/figures/segment11_*.png`.
- **2026-09-13** (new session) — Segment 12: the two remaining Tier 1/2/3 candidates
  from Segment 10 Task 2's literature search, both as separate gated/additive changes,
  no other candidate started. **First, a correction**: re-deriving Task 3's "20 of 95
  VIPL subjects (21%) run at a true ~16fps" figure from the same CSV found 44 of 95
  (46%) instead — a genuine counting error, not a different definition (likely
  conflated with Segment 6 Task L's unrelated 20-subject v5-scenario figure). Corrected
  in `docs/Segment10_Task3_Tier0_Diagnostics.md` and this file with strikethrough.
  **Task 1 (mid-band mode)**: checked first, per the brief's instruction, whether
  today's `'wide'` mode actually errors for the affected subjects — it does NOT (real
  fps is always fractionally above the exact 16.0fps that would trip the guard), though
  it runs with a razor-thin 0.033-0.322Hz margin vs. `'mid'`'s comfortable ~2.0-2.3Hz.
  Regression check passed (fresh `'wide'` recompute matches Task 1's own cached numbers
  100/100) before trusting the `'mid'` numbers built the same way. Result: only 6/100
  subjects show any difference at all (fftHeartRate's fixed 0.7-4Hz search band is
  insensitive to this band-edge choice for almost everyone); 3 flip from failing to
  passing the 0.3 notch-confidence bar, 0 regress — but only 1 of 3 is in the
  hypothesized near-Nyquist "affected" group, so the mechanism is NOT what Task 3
  predicted. Kept production on `'wide'`; `'mid'` is now a validated, low-risk,
  available alternative, not promoted to default. Full detail:
  `docs/Segment12_Task1_Mid_Band_Evaluation.md`. **Task 2 (Harmonic-Selective Gaussian
  Filtering)**: new `morphology/harmonicSelectiveGaussianFilter.m`, full formula read
  from the primary source (PMC13307314) this session. At the paper's own literal
  alpha=0.5, underperforms the current ABPF comb on pass rate (20% vs 24%) and median
  waveform correlation (0.383 vs 0.519), with a verified mechanistic explanation
  (adjacent harmonics' Gaussians overlap heavily at this pool's typical HR, so the
  filter stops being selective — visualized directly). A follow-up alpha sweep
  (0.10-0.50) found alpha=0.15 beats ABPF on all three metrics at once (31% pass rate,
  0.523 median corr, 3% harmonic confusion) — but 17/100 subjects show a severe
  notch-confidence regression even as the pool median improves, reported plainly rather
  than only citing the favorable median. Neither parameter adopted; flagged as the most
  promising open lead in the whole document. Full detail:
  `docs/Segment12_Task2_Harmonic_Selective_Gaussian_Filter.md`. Outputs:
  `matlab/src/morphology/harmonicSelectiveGaussianFilter.m`,
  `matlab/scripts/run_segment12_task1_mid_band_evaluation.m`,
  `matlab/scripts/run_segment12_task2_gaussian_harmonic_filter_evaluation.m`,
  `matlab/scripts/run_segment12_task2b_gaussian_alpha_sweep.m`,
  `results/metrics/segment12_task1_mid_band_comparison.csv`,
  `results/metrics/segment12_task2_gaussian_vs_abpf_comparison.csv`,
  `results/metrics/segment12_task2b_gaussian_alpha_sweep.csv`,
  `results/figures/segment12_*.png`. `cpaceProjection.m`, `computeCrossROIPLV.m`, and
  `residualAdaptiveKalmanHR.m` were not touched, per this session's own instruction.
- **2026-09-13** (new session) — Segment 13: closed the open thread from Segment 12
  Task 2 (the 17-subject regression under `harmonicSelectiveGaussianFilter.m` at
  alpha=0.15, previously measured but not explained). **Action 1**: pulled per-subject
  results from Segment 10/11/12's own existing, already-validated CSVs (no video
  reprocessed) and checked five hypotheses, reporting all — dataset (weak/small-N),
  device/source (inapplicable, no variation in this pool), HR range (not a separator),
  skin-colour angle (ruled out) — and found a clean one: **all 17/17 severe
  regressors were subjects the current ABPF comb already passed** (0/76 ABPF-failing
  subjects regressed). Several sit exactly at `notchDetectIEM.m`'s own documented
  confidence-clip ceiling (1.000), consistent with a "more room to fall than to rise"
  mechanism; waveform correlation (uncapped) doesn't show the same pattern for the same
  subjects. **Action 2**: built and evaluated (on real, freshly recomputed signals, not
  cached-CSV arithmetic) a new gated function, `morphology/harmonicFilterConfidenceGate.m`
  — keep ABPF wherever it already passes, substitute Gaussian(0.15) only where it
  fails. Result: pass rate 24%→31%(Gaussian alone)→**47% (gated)**, median corr
  0.519→0.523→**0.522**, harmonic confusion 5%→3%→**3%**, **zero severe regressions**
  (structural, not just empirical). Also tested and explicitly warned against in the
  new function's own header: a multi-candidate "pick the highest self-reported
  confidence" variant hits 64% pass rate but its median corr (0.508) is the WORST of
  every method compared — a demonstrated selection-bias artifact, flagged so it isn't
  mistaken for a real gain later. **Not adopted into production** — the gate stays a
  new, gated, off-by-default utility, per the brief; `cpaceProjection.m`,
  `computeCrossROIPLV.m`, `residualAdaptiveKalmanHR.m`, and the `'wide'` bandpass
  default were all left untouched. Full detail:
  `matlab/docs/Segment13_Task1_Gaussian_Regression_Root_Cause_and_Gate.md`. Outputs:
  `matlab/src/morphology/harmonicFilterConfidenceGate.m`,
  `matlab/scripts/run_segment13_task1_regression_root_cause.m`,
  `matlab/scripts/run_segment13_task2_gated_selection_evaluation.m`,
  `results/metrics/segment13_task1_regression_root_cause.csv`,
  `results/metrics/segment13_task2_gated_evaluation.csv`, `results/figures/segment13_*.png`.
- **2026-09-13** (new session) — Segment 14: promoted
  `morphology/harmonicFilterConfidenceGate.m` from a gated utility (Segment 13) to Branch
  2's production default. **Action 1**: found genuinely held-out ground-truth data — UBFC
  DATASET_2, 42 subjects, confirmed never touched by any prior segment — extracted it
  (targeted per-entry zip extraction, matching the VIPL precedent) and ran Segment 13's
  exact comparison unmodified. Found and root-caused a real data-quality issue (9/42
  subjects have a duplicate ground-truth timestamp, tripping `resampleUniform.m`'s
  `pchip` interpolation — an existing function, not touched), excluded those 9 rather than
  working around them, leaving n=33. Result: the gate's zero-severe-regression property
  replicated exactly on held-out data (pass rate 45%→58%, median corr 0.364→0.520), while
  plain Gaussian(0.15) alone showed 13/33 (39%) severe regressions — proportionally worse
  than the audit pool. Full detail:
  `docs/Segment14_Task1_UBFC_D2_Held_Out_Validation.md`. **Action 2**: checked first (per
  the brief) whether Branch 2 runs through `run_segment3_filtering_batch.m`/
  `run_vipl_integration_batch.m` — it does not (Branch 1-only scripts); wired the new
  `opts.useConfidenceGate` (default `true`) into the real orchestrator,
  `pipeline/estimateVitalsAndMorphology.m`, instead, computing the Gaussian candidate only
  when ABPF's own confidence fails the 0.3 bar. Updated
  `tests/segment7_task_f_regression_test.m` to pin its ABPF-specific check to
  `useConfidenceGate=false`; re-ran it, all 3 parts still pass. Regenerated
  `results/metrics/segment7_task_b_notch_branch2.csv` with an additive `confidenceGate`
  condition (old file preserved as `..._preconfidencegate.csv`) — found and reported
  honestly that the gate makes literally no difference on this original 5-subject
  benchmark (still 4/5 pass), since only 1 subject is eligible and it isn't rescued.
  **Action 3**: confirmed directly from existing Android docs (not guessed) that Branch 2
  was never ported to Android — no Android work done. Full detail:
  `docs/Segment14_Task2_Confidence_Gate_Production_Promotion.md`. `README.md` and
  `docs/Spandan_Final_Pipeline_Report.md` updated to describe the new default.
  `cpaceProjection.m`, `computeCrossROIPLV.m`, `residualAdaptiveKalmanHR.m`, and the
  `'wide'`/`'mid'` bandpass default were all untouched, per this session's own scope.
- **2026-09-14** (new session) — Segment 15: implemented and evaluated cPACE Stages
  2-3 (eigenvector-based cardiac extraction + homodyne amplitude normalization) on top
  of Segment 11 Task 1's Stage 1, per Kaur, Lakshminarayanan & Saini's paper. Briefed as
  "Segment 14" — renumbered to 15 before writing code, since Segment 14 already exists
  (above) and is a different, completed body of work; nothing was actually missing from
  this file, the brief's own number was stale. **Two corrections made against the real
  paper before implementing** (both the main paper PDF and Supplement 1 PDF are in
  `Research Paper/`, read directly): (1) the brief asserted the paper has no
  second-candidate eigenvector selection — false, Section 4.2 describes a two-candidate
  multi-ROI PLV consensus (cPACE-v1 vs. cPACE-absorption); asked the user, decided to
  implement dominant-eigenvector-only anyway (matches Table S2's literal row; this
  project only has multi-ROI data for 20 of the 100 subjects). (2) all of the brief's
  quoted Table S2 parameter values (bw=0.30Hz, fenv=0.30Hz, kappa=2, 0.7-3.0Hz cardiac
  band, filter orders, sensitivity-sweep ranges) were verified directly against the
  real Table S2 and matched exactly. **New**: `pulseextraction/cpaceEigenExtract.m`,
  `cpaceHomodyneNormalize.m`. **One real ambiguity found and fixed via real-data
  testing, not assumed**: implementing the paper's Eq. 9 literally (projecting the WIDE
  0.7-3.0Hz signal onto the dominant eigenvector before the Hilbert transform) gave HR
  MAE 16.2bpm on this project's 100-subject pool — a clearly broken result, traced to
  Hilbert instantaneous phase requiring a near-monocomponent input (the same
  precondition `computeCrossROIPLV.m`'s own header already states), which a 2.3Hz-wide
  signal is not. Fixed by projecting the already-narrowband seed+/-bw signal (the same
  one the eigenvector was derived from) instead — MAE improved to 10.1bpm at the
  default bw=0.30, a real but far more plausible result. Documented as a resolved
  ambiguity (Table S2 is silent on which signal feeds this step), not a silent
  deviation. **Task 3 (bw swept over {0.15, 0.30, 0.50}Hz, real 100-subject pool,
  per-subject)**: confirms bw is the sensitive parameter the paper's own Supplement
  flags, but per-subject swings (up to ~40bpm for 2 UBFC-D1 subjects at bw=0.50) are far
  larger than the paper's own reported pooled 0.99-2.88bpm swing — the same
  pooled-vs-per-subject lesson as Segment 12's 17-subject regression. Narrower
  (bw=0.15) is pooled-best on this mostly-resting cohort, matching the paper's own
  caution about narrow-HR-range cohorts. **Task 4 (full pipeline vs. production and
  Stage-1-only)**: full cPACE does not beat production at any bw (best pooled: 8.66bpm
  at bw=0.15 vs. production's 7.86-7.87bpm); 42/100 subjects regress >1bpm vs. POS,
  24/100 severely (>10bpm), several already-accurate subjects made badly wrong.
  Cross-ROI PLV (20-subject VIPL pool) DOES improve slightly at every bw tested
  (0.279-0.295 vs. production's 0.254-0.271) — a genuine phase-coherence gain even as
  HR-MAE regresses, on a cohort Segment 11 already found sits in the paper's
  least-favorable (low skin-colour-angle) regime. **Kept gated/off-by-default**, same
  discipline as `cpaceProjection.m` and the confidence gate's own multi-candidate mode
  — this segment's job was an honest result, not a production promotion. Full detail:
  `docs/Segment15_Task1_cPACE_Eigen_Extract.md`, `Segment15_Task2_cPACE_Homodyne.md`,
  `Segment15_Task3_Hyperparameter_Sweep.md`, `Segment15_Task4_Evaluation.md`. Outputs:
  `matlab/src/pulseextraction/cpaceEigenExtract.m`,
  `matlab/src/pulseextraction/cpaceHomodyneNormalize.m`,
  `matlab/scripts/run_segment15_task3_task4_cpace_full_evaluation.m`,
  `results/metrics/segment15_cpace_full_per_subject_hr.csv`,
  `results/metrics/segment15_cpace_full_summary_hr.csv`,
  `results/metrics/segment15_cpace_full_per_subject_plv.csv`,
  `results/metrics/segment15_cpace_full_summary_plv.csv`,
  `results/metrics/segment15_task3_bw_sweep_per_subject_regressions.csv`,
  `results/metrics/segment15_task4_vs_production_per_subject_regressions.csv`,
  `results/figures/segment15_*.png` (3 figures). `README.md` updated.
- **2026-09-14** (new session) — Segment 16: Android app, three independent tracks
  (HR/PPG stability, SpO2 rigor, UI/UX), `matlab/` untouched per the brief. Started
  with **no physical device** (the local Pixel_7 AVD emulator was tried and never
  finished booting, 20+ minutes stuck `offline` despite passing its own
  acceleration checks) — **a real device (the same Galaxy A35 this project has
  always used) became available partway through, and most of this IS on-device-
  verified, not just built/tested.** **Task 1**: `signal/DisplaySmoother.kt`,
  display-level-ONLY rolling-median/EMA smoothing of the already-switched bpm
  value, explicitly NOT RAKF/Kalman (`matlab/docs/Segment6_Task5_RAKF_Kalman_
  Smoothing.md` already found that the worst of six methods on real MATLAB data).
  Unit tests caught a null-handling bug before any device work. **Real on-device
  A/B capture (83 distinct recomputes, ~66s): mean tick-to-tick HR jitter cut
  17.46→5.49bpm (−69%), stdev 24.63→20.54, zero accuracy cost.** That same capture
  surfaced a SECOND real bug (the UI ticks 5× faster than the pipeline recomputes,
  so the "5-tick" median window was re-ingesting one value up to 5× instead of
  spanning 5 independent measurements) — fixed via input de-duplication, unit
  tests grew 6→8. **Promoted `ENABLE_HR_DISPLAY_SMOOTHING_DEFAULT` to `true`** on
  this real (if single-session) evidence. Also derived the DSP fact the brief's
  fps/window-length question needed: FFT bin resolution is `1/(window duration)`,
  independent of sampling rate — window-length re-test itself not run this
  session (device time went to the smoothing bug instead). **Task 2**: confirmed
  live BOTH at the code level and freshly on real hardware (SpO2 chip visibly
  updating, `logcat` showing real R/SpO2 co-movement, zero crashes). 2023+
  literature search (VERIFIED-FULL/VERIFIED-INDEX/BLOCKED discipline, ~10 sources)
  found no independently-validated calibration this segment could responsibly
  adopt (strongest lead trains on a different modality, wrist IR/red contact PPG,
  that doesn't transfer) — **no calibration change made, said so plainly**. Added
  instead: per-channel perfusion index now exposed/logged (real values on record
  for the first time, 0.007-0.038 observed), and the existing degenerate-signal
  guard is now a named `LOW_SIGNAL_QUALITY` status. **Task 3**: `activity_main.xml`
  redesigned into a rounded "vitals card" with per-metric status pills
  (`EstimatorStatus` plus a UI-only `NO_FACE` case) and a debounced "No face
  detected" banner — answering the brief's "no face detected"/"low confidence"/
  "warming up" request directly. **Real before/after captures verified
  on-device** (git-stashed to rebuild the genuine "before" layout), all three
  states captured (live/warming-up/no-face); **a real text-wrap bug found via the
  first capture and fixed** (redundant "HR:"/"SpO2:" prefix dropped). One XML
  `--`-in-comment build failure hit twice and fixed both times (same pitfall this
  project's Android README already documented once before). **[2026-09-14, later
  same session] All screenshot files and the published gallery artifact deleted
  at the user's request** (contained the subject's face) — confirmed never
  committed to git and never reached GitHub (untracked local files at deletion
  time; this project's actual last commit predates this task). Full detail:
  `android/docs/Segment16_Task1_HR_Stability.md`,
  `Segment16_Task2_SpO2_Research_and_Audit.md`, `Segment16_Task3_UI_UX_Pass.md` (all
  three updated with real results, screenshot references removed).
  `android/README.md` updated with a full Segment 16 summary.
- **2026-09-14** (Cowork session) — Segment 17: `scripts/run_spandan_interactive.m`
  rewritten to call `pipeline/estimateVitalsAndMorphology.m` and every other pipeline
  function off the MATLAB path (self-locating `addpath` bootstrap added) instead of
  ~1200 lines of Segment-7/8-frozen local duplicates, per Abrar's request for one file
  that runs the current pipeline on any video picked from anywhere on the computer.
  Drops the old file's `chooseHeuristicPolarityByNotchConfidence` divergence for
  no-ground-truth clips (never ported into `matlab/src/` — flagged as a follow-up, not
  done this session). Not run in MATLAB this session (no MATLAB available in this
  environment) — should be run once to confirm. See Current State and Active Work
  Queue entries above for full detail.
- **2026-09-15/16** (new session) — Two independent Android workstreams, both with real
  on-device verification on the same Galaxy A35 (`RFCXC0FFFSN`) once it was attached
  partway through the session (started with none, per this project's recurring pattern —
  see the Segment 18/19 Active Work Queue entries for exactly when device access
  resumed). **Segment 18** (camera throughput + buffer window): re-profiled the current
  N=3-detection-skip path (confirmed ML Kit detection still ~98% of cost, nothing shifted
  the bottleneck), built a new gated (`useMotionTracking`, off by default)
  `OpticalFlowFaceTracker`/`OpticalFlowMatcher` inter-detection tracker plus a new
  `CoordinateMapper.sensorRectToRotatedRect` inverse mapping, and re-measured real
  fps three times back-to-back: baseline 19.96/19.19fps steady-state (two captures,
  confirming the existing mechanism), tracking-enabled 16.33fps — a real, unrounded-up
  **negative result**: the tracker's own cost is negligible but end-to-end throughput
  regressed for a reason a controlling re-check couldn't attribute to simple thermal
  drift; kept off by default, root cause flagged as open (no profiling tools available
  to fully isolate it). `WINDOW_DURATION_SECONDS` left at 25.0s — no new evidence changes
  Segment 16's tradeoff analysis. **Segment 19** (Branch 2 port): read all nine relevant
  `matlab/src/morphology/*` and `pipeline/estimateVitalsAndMorphology.m` files directly
  from source, then ported the full Branch 2 chain to Kotlin (`PchipInterpolator`,
  `MorphologyBandpassFilter`, `AdaptiveHarmonicFilter`, `HarmonicSelectiveGaussianFilter`,
  `HarmonicFilterConfidenceGate`, `FixPolarity`, `ResampleUniform`, `EnsembleAverageBeats`,
  `NotchDetectIEM`, orchestrated by a new `MorphologyWaveformEstimator` that reuses the
  existing `EstimatorStatus` enum rather than inventing a new one) — this project's first
  time Branch 2 has ever run on Android, correcting every prior session's accurate-at-the-
  time "never ported" claim (marked superseded, not deleted, per this file's own
  Maintenance Protocol). Added a new "WAVEFORM MORPHOLOGY (BRANCH 2)" UI card surfacing
  the RAW (unclipped) notch confidence number, not just a pass/fail. 49/49 unit tests pass
  (10 new files, all synthetic-signal-verified first). **Real on-device capture**: 9
  successful Branch 2 recomputes over ~40s, zero crashes, real WIDE/MID band-mode
  switching and real ABPF/Gaussian confidence-gate substitution both observed live (not
  just unit-tested), Branch 1 (HR/SpO2) confirmed unaffected on the same capture. Full
  detail, all caveats and flagged ambiguities, in each segment's own doc:
  `android/docs/Segment18_Camera_Throughput_And_Buffer_Window.md`,
  `android/docs/Segment19_Branch2_Morphology_Port.md`.
- **2026-09-20** — Segment 18 (MATLAB colour-space ablation): a*/Cb/Cr vs green on 112 subjects plus a 20-subject VIPL v2 motion pool. a* beats green but not CHROM/POS, PLV does not support it; not promoted. See the Active Work Queue entry and `matlab/docs/Segment18_ColorSpace_Ablation.md`.
- **2026-09-20** — Segment 21 (literature search, motion-robust combiners): opened by Segment 18's motion-pool collapse. Read PBV/LGI/OMIT in full (Segment 10 Task 2's own Tier 2 item 14, never previously read), added 2SR and the VIPL-HR dataset paper's own motion-scenario context. Ranking: LGI > 2SR > PBV > OMIT for this specific problem, nothing implemented yet — queued as Segment 22. Added `matlab/docs/Literature_Review_Master.md`, a consolidated cross-project paper index (everything in Segment 10 Task 2 plus this segment), for future sessions to check before starting a new search. See `matlab/docs/Segment21_Motion_Robust_Combiner_Literature_Search.md`.
- **2026-09-20** — Segment 22 (motion-robust combiner implementation + stratified evaluation): closed Segment 21's line. NO-GO for both 2SR and LGI (projection-only, tracker not built) — a Tier 0 check found production CHROM/POS already beats both on the v2 motion pool (never measured before this segment) and the main pool, pooled and stratified by skin-angle/dataset/motion-level/frame-rate. Production pipeline unchanged, nothing promoted. See the Active Work Queue entry and `matlab/docs/Segment22_Motion_Robust_Combiner_Evaluation.md`.
- **2026-09-20** — Segment 23 (fairness / native-form audit): re-ran every "EVALUATED, NOT ADOPTED" candidate in its native or completed form (T1 cPACE windowed q̂, T2 CIELab a* native ROI+KLT+Lab, T3 2SR + YCbCr skin mask, T4 LGI own read-out + state-space tracker, T5 19-combiner × 6-read-out matrix, T6 CHROM/POS de-tuned to the papers' generic forms, T7 RAKF Eq. 12 exponent) on 112 + 20 subjects, per pool. All regression checks against earlier results exact. **No verdict changed; production untouched (18/18 protected files SHA-256 identical).** Conclusion: mostly real robustness, modest tuning/read-out asymmetry that changes no ranking; new read-out-stage CANDIDATE for CHROM/POS (windowed/tracked read-out, −1.1..−1.5bpm MAIN_112 MAE) awaits held-out validation. Several brief premises were corrected against the primary papers (Yang cell size, Kaur q̂ not windowed, Pilz benchmark read-out is FFT, Debnath & Kim no numeric β; CHROM primary text BLOCKED). See `matlab/experiments/segment23_fairness_audit/MASTER_REPORT.md` and the Active Work Queue / Current State entries.
- **2026-09-20** — Segment 24 (read-out held-out validation): preregistered one-shot; UBFC-D2 found previously used (Segment 14) and no unused VIPL subjects exist, so PRIMARY = unused VIPL videos (v7/v4/v6 source1, held out by video not subject), D2 = second look. As-tested windowed/tracker read-outs NOT validated; band-matched windowed read-out clearly better (candidate, unvalidated). See `matlab/experiments/segment24_readout_heldout_validation/REPORT.md`.
- **2026-09-20** — Segment 25 (read-out replication): MAIN_112 holds, unseen scenarios v3+v5 replicate (Holm p 0.020/0.0007), unseen camera (v1 source3) does not. Band-matched windowed read-out promoted CANDIDATE, NOT VALIDATED → ~~CANDIDATE, VALIDATED (scenario-generalizing)~~ CANDIDATE, VALIDATED — degraded-signal conditions only (dark/low-fps/motion; not shown in normal-lighting or cross-device conditions); not adopted. See `matlab/experiments/segment25_readout_replication/REPORT.md`.
- **2026-09-20** — Segment 26 (read-out mechanism): fixed Segment 25 verdict wording (degraded-signal conditions only; v4/v6 are not motion). Median vs mean aggregation: median-rejection NOT the mechanism (mean recovers ~90–100 % of gain on degraded sets, no Holm-significant difference). No cached quality proxy (fs, dropped frames, brightness) tracks the gain. Mechanism still unknown. See `matlab/experiments/segment26_readout_mechanism/REPORT.md`.
- **2026-09-20** — Segment 27 (proposed third mechanism-isolation attempt for the Segment 24–26 read-out finding) was designed but deliberately NOT run — after two dedicated segments (26's median-vs-mean and quality-proxy tests) came back negative, further mechanism-hunting was judged to have hit diminishing returns with no production decision pending on the answer. Final resting verdict: CANDIDATE, VALIDATED — degraded-signal conditions only; mechanism unresolved; not adopted; no further investigation planned absent new evidence. Full consolidated summary of Segments 23–26: `matlab/docs/Fairness_Audit_Summary_Segments23-26.md`.
- **2026-09-20** — Wavelet-denoise fix promoted into `estimateVitalsAndMorphology.m`; GREEN splice artifact superseded; SpO2 pinned to pre-wavelet; Branch 2 and SpO2 under wavelet preregistered as deferred (Segment 27). See the Current State entry of the same date.
- **2026-09-25** — Segment 27 (Branch 2 notch and SpO2 under wavelet denoising, EXECUTED — the preregistration's own Segment-number reuse note applies; this is the wavelet-evaluation Segment 27 from `matlab/experiments/segment27_branch2_wavelet_evaluation/PREREGISTRATION.md`, not the unrelated read-out mechanism-isolation Segment 27 logged above, which stayed un-run). Parity gates passed first (Item A: byte-for-byte against `segment7_task_b_notch_branch2.csv`; Item B: per-subject R exact against both frozen calibration CSVs, pooled LOSO MAE/RMSE exact against `segment6_spo2_loso_metrics.csv`, Pearson_r within a documented 0.001 tolerance — see that script's own comment for why: the frozen CSV's downstream numbers were computed from R already text-rounded to ~5 significant digits, so a freshly regenerated full-precision R feeding an already-weak r≈-0.38 correlation is expected to diverge at that scale). **Item A verdict: HARMFUL** — adaptiveHarmonic notch pass count (UBFC 5-subject pool, confidence ≥0.3) dropped 4/5 → 2/5 under wavelet, with two previously-passing subjects falling below the bar (7-gt 0.6405→0.1727, 12-gt 1.0000→0.0380). Consequence applied: Branch 2 pin added to `estimateVitalsAndMorphology.m` (Branch 2's detrend chain, wide-band f0 estimate, and both ABPF/Gaussian harmonic-comb candidates now always run on pre-wavelet R/G/B, regardless of `opts.useWaveletDenoise` — same "capture before reassignment" pattern as the existing SpO2 pin). This also resolves that file's own previously-flagged regression-test staleness note: `tests/segment7_task_f_regression_test.m` Part 3 passes again unmodified (reverified). Android's `MorphologyWaveformEstimator.kt` was ported before the wavelet default existed and already has no wavelet step, so **no Android change needed** — confirmed still matching post-pin. **Item B verdict: NO DEMONSTRATED DIFFERENCE** — pooled N=112 LOSO MAE moved only 1.8519→1.8570pp (well under the ±0.10pp decision threshold either direction), Wilcoxon signed-rank on paired |error| p=0.216 (not significant). SpO2 pin stays; `calibrateSpO2.m` and both frozen calibration CSVs untouched; **no Android change** to `LiveSpo2Estimator.kt` (already independent of the wavelet chain). Protected-file SHA-256 before/after confirms only `estimateVitalsAndMorphology.m` changed (Item A pin) — `calibrateSpO2.m`, both frozen calibration CSVs, `segment7_task_b_notch_branch2.csv`, `segment6_spo2_loso_metrics.csv`, and both named Android estimator files are byte-identical. New files under `matlab/experiments/segment27_branch2_wavelet_evaluation/`: `scripts/s27_branch2_wavelet.m`, `scripts/s27_spo2_wavelet.m`, `results/s27_branch2_parity_check.csv`, `results/s27_branch2_wavelet.csv`, `results/s27_spo2_per_subject.csv`, `results/s27_spo2_wavelet_metrics.csv`, `results/protected_files_{before,after}.sha256`.
- **2026-09-25** — Segment 28 (camera throughput improvement attempt, continues Segment 18 -- that doc's own "Honest verdict" section is unchanged). Fixed Segment 18's own leading hypothesis: `OpticalFlowFaceTracker.track()`'s two per-skipped-frame `IntArray` allocations, now reused class-level buffers. Added a new candidate, off by default: `CroppedDetectionStrategy` (new file) runs real ML Kit detection on a small padded crop around the last known face box on skipped-detection frames instead of freezing/tracking it, with integer downscale support in the same code path; wired into `FaceAnalyzer.kt` (`useCroppedDetection` flag) and `ProfilingFaceAnalyzer.kt` (new `cropMs` phase + miss counter). 8 new unit tests for the pure crop-rect math (57/57 total pass). Found and flagged (not fixed, out of scope): `android.graphics.Rect`'s 4-arg constructor is a no-op under this project's plain-JUnit harness (`isReturnDefaultValues=true`), which means the existing `CoordinateMapperTest.kt` has been passing vacuously (compares zeroed rects against zeroed rects) -- production `CoordinateMapper.kt` itself is unaffected on a real device. This segment's own new test avoids the same trap via an explicit-field-assignment helper. **A device (same Galaxy A35, `RFCXC0FFFSN`) was connected later this session and real captures were run** (`ProfilingFaceAnalyzer` swap, `adb logcat`, reverted clean before the final build): `useMotionTracking=true` measured 21.27fps against a same-session baseline that itself ranged 18.80-21.45fps across two captures -- i.e. the allocation fix closed Segment 18's clear 16.33-vs-19.19/19.96fps regression (motion tracking now sits inside baseline's own noise band, though not demonstrated to beat it). `useCroppedDetection` at downscale=1 was a clear loss (13.12fps, `cropMs` mean 66.33ms, max 308.70ms); at downscale=2 it also landed inside the baseline noise band (20.37fps, `cropMs` mean 18.52ms, max 159.09ms). **No new default promoted** -- `useMotionTracking`/`useCroppedDetection` stay `false`, `DETECT_EVERY_N_FRAMES` stays 3; none of this session's candidates cleared the bar of a reproducible improvement over baseline's own measured session-to-session noise. Final device state: plain-`FaceAnalyzer` production build (all this segment's code fixes included, no flags flipped) installed and force-stopped, ready to launch. Full detail and what would make a future re-measurement more conclusive: `android/docs/Segment28_Throughput_Improvement.md`.
- **2026-09-25** — Segment 29 (ML Kit `minFaceSize` tuning + Kalman box tracking), following a literature/GitHub research pass after Segment 28 found no candidate there beat baseline. Two new levers, both **PROMOTED TO DEFAULT** after real on-device measurement (same Galaxy A35, `RFCXC0FFFSN`), bracketing baselines before/after each candidate this time (learning from Segment 28's own noise-band finding): raising `FaceDetectorOptions.minFaceSize` from ML Kit's default 0.1 to **0.35** cut mean real-detection cost ~87-90ms → ~19-25ms (~4.7x, confirmed real via a stable bracketing baseline, not noise) and raised fps ~18.5-19 → ~23.7-23.84, with 0-1 missed-face frames per ~750-1000 including a deliberate increased-camera-distance check (0/744 missed). New `KalmanBoxTracker.kt` (constant-velocity Kalman filter over box center/size, decomposed into four independent 1D filters) replaces the frozen box/`OpticalFlowFaceTracker` on skipped frames when enabled -- a different risk class from pixel-content trackers (never reads pixel data, so cannot inherit the KLT drift failure mode `matlab/docs/Segment7_Task_D_Landmark_ROI.md` documented), measured cost negligible (0.03-0.04ms mean, ~3ms max) and composes cleanly with the `minFaceSize` change. 7 new unit tests (64/64 total pass). Honest caveat carried into the doc: Kalman's promotion rests on "free + plausible upside + no measured downside," not a validated ROI-positional-accuracy win against real ground truth (only synthetic-motion unit tests). `useMotionTracking`/`useCroppedDetection` stay `false`, `DETECT_EVERY_N_FRAMES` stays 3 -- Segment 28's verdicts on those are unchanged. Final device state: production `FaceAnalyzer` build with the new defaults installed, confirmed running without crashes on-device with a live face for 10+ seconds, then force-stopped. Full detail: `android/docs/Segment29_MinFaceSize_And_Kalman.md`.

# Segment 7 Task D — Landmark/KLT-Tracked Forehead ROI

Continues Segment 7 Tasks A-C (`Segment7_Task_A_Morphology_Pipeline.md`,
`Segment7_Task_B_Notch_Quantification.md`, read first; nothing already established
there is re-derived here). Task B established that `morphology/adaptiveHarmonicFilter.m`
(ABPF), applied per-channel before `pulseextraction/chromCombine.m`, is the
best-supported single intervention for dicrotic-notch recovery on this project's
5-subject UBFC pool: 4/5 subjects land above the >=0.3 confidence noise floor. Task C
confirmed `morphology/tiledROIExtraction.m` (spatial ROI tiling) does not help and does
not compose with ABPF.

**Bottom line, stated up front**: this task's landmark/rotation-compensated ROI is
also a **negative result**, and a larger one than Task C's. Baseline ABPF-only reaches
**4/5** subjects above the 0.3 bar; Landmark/KLT-ROI+ABPF reaches only **2/5** — it
**regresses** two subjects ABPF-only already had confidently (5-gt, 6-gt, both drop
from comfortably above the bar to essentially zero), and it does **not** recover the
one subject ABPF-only still misses (after-exercise) — that subject's confidence gets
**worse**, not better, under the tracked ROI. This is the third ROI-stage or
architecture experiment in this project (after Task N's multi-region ROI switching and
Task C's tiling) to find that changes to *where* pixels are sampled from do not help
this specific target on this specific pool, while ABPF's *spectral* change remains the
one intervention that reliably does.

## Action 0 — Toolbox check: no facial-landmark / face-mesh detector available

Checked this MATLAB R2024b installation (per the README) for any way to build the
4-landmark forehead ROI the uploaded thesis's Section 3.2.1 specifies (indices 67, 297,
105, 334 on a 468-point face mesh):

- `ver` (all ~113 installed toolboxes) -- no Computer Vision Toolbox face-landmark
  function, no dedicated face-mesh toolbox.
- `matlab.addons.installedAddons` -- lists only the standard MathWorks toolboxes
  themselves (as "addons"); no Deep Learning Toolbox Model support package for face
  landmarks/mesh is installed.
- Direct `exist()` probes for `facemark`, `faceLandmark`, `facialLandmark`,
  `landmarkDetector`, `mediapipe`, `faceMesh`, `shapePredictor`, `LiveLinkFace`,
  `faceLandmarkDetector` -- **all empty**. Nothing by any of these names exists on the
  path.
- `vision.PointTracker`, `detectMinEigenFeatures`, `detectHarrisFeatures`, and
  `estimateGeometricTransform2D` **are all present** (Computer Vision Toolbox is
  installed and confirmed working via `vision.CascadeObjectDetector`, already a project
  dependency).

**Conclusion: no facial-landmark / face-mesh detector of any kind exists on this
machine.** The 4-named-landmark geometry cannot be built, tracked, or approximated by
landmark identity here, with or without tracking. Per the task's own Action 0 branching
instruction, this fired the **KLT-tracked rotation-compensation fallback**: track
corner features within the SAME axis-aligned forehead box `roi/extractROISignals.m`
already uses, and let a per-frame similarity transform re-orient that box to follow
head rotation, instead of reproducing the thesis's specific landmark geometry (which is
simply not buildable in this environment). See `roi/landmarkROIExtraction.m`'s own
header for the full algorithm description and the explicit statement that this targets
a narrower, adjacent question ("does rotation compensation help", not "does the
thesis's exact 4-landmark ROI help").

## Action 1 — `roi/landmarkROIExtraction.m`

New file, additive, in `roi/` (not `morphology/`) alongside `extractROISignals.m`,
matching this project's stage-based folder convention -- this is a Stage 1 (ROI
extraction) function, not a post-extraction processing step. Does not modify
`roi/extractROISignals.m` in any way.

Returns raw, per-channel `R`, `G`, `B` (1 x numFrames each, same shape/units as
`extractROISignals.m`'s own output) -- **not** a pre-combined pulse signal, per this
task's explicit confound-avoidance instruction and Task C1's own lesson about
pipeline-position mismatches. `adaptiveHarmonicFilter.m` and `chromCombine.m` run at
their established, correct position (per-channel, before projection) in
`scripts/run_segment7_task_d_landmark_roi_batch.m`, identical to
`scripts/run_segment7_task_b_branch2_batch.m`'s own adaptive-harmonic condition.

Algorithm: Viola-Jones face detection every 5th frame (same `detectEveryN`, largest-box
convention as `extractROISignals.m`) -> forehead sub-region from the SAME fractions
(`x:[0.30,0.70] y:[0.10,0.30]`) -> `detectMinEigenFeatures` restricted to that box ->
`vision.PointTracker` tracks those points forward -> `estimateGeometricTransform2D`
(similarity transform, anchor-frame points vs. current-frame points, not
frame-to-frame incremental) -> transform applied to the anchor box's 4 corners ->
rotated polygon sampled via `poly2mask`. Re-anchors (fresh detection + fresh feature
selection + tracker reinit) at the same 5-frame cadence, bounding KLT drift. Falls back
to the last good polygon if too few points survive tracking or the transform produces
an implausible area change (documented thresholds, not from any paper). Algorithm
*concept* adapted from van der Kooij & Naber (Behav Res Methods 51:2106-2119, 2019) /
`marnixnaber/rPPG` -- that repository is GPL-3.0, this project is MIT, so only the
algorithm's shape was read, no code was copied; see the function's own header for the
full attribution statement.

Smoke-tested on subject 5-gt's full 2409-frame clip before the batch run: passed,
37 s, 0 dropped/fallback frames, 8 debug samples captured correctly.

## Action 2 — Batch script and results

`scripts/run_segment7_task_d_landmark_roi_batch.m`. Shared f0 for the harmonic comb
comes from the EXISTING baseline decode (`extractROISignals.m` + `bandpassMorphology.m`
`'wide'` + `chromCombine.m`), the same source/method
`run_segment7_task_b_branch2_batch.m` and `run_segment7_task_c2_true_combined_batch.m`
already use -- so both conditions in the table below share the exact same f0 operating
point, and the only thing that changed between them is the ROI stage.

`results/metrics/segment7_task_d_landmark_notch.csv`, all 5 subjects, 0 failures, 0
dropped/fallback frames on every single subject (the KLT tracker never had to fall back
to a stale polygon on this pool -- worth stating plainly, since it rules out "the
tracker kept losing the ROI" as the explanation for what follows).

## Action 3 — Comparison table: Baseline-ROI+ABPF vs Landmark/KLT-ROI+ABPF

Baseline column is `results/metrics/segment7_task_b_notch_branch2.csv`'s
`adaptiveHarmonic` row per subject (Task B's own established 4/5 result, reproduced
here unchanged). Both conditions run the identical ABPF chain at the identical shared
f0; only the ROI stage differs.

| Subject | Baseline confidence | Baseline >=0.3? | Landmark/KLT confidence | Landmark confidenceRaw | Landmark >=0.3? | Outcome |
|---|---|---|---|---|---|---|
| 5-gt | 0.7447 | **YES** | 0.0127 | 0.0127 | **NO** | **Regression** -- confident subject lost |
| 6-gt | 0.4120 | **YES** | 0.0134 | 0.0134 | **NO** | **Regression** -- confident subject lost |
| 7-gt | 0.6405 | **YES** | 0.5937 | 0.5937 | **YES** | Small regression, same side of bar |
| 12-gt | 1.0000 (clipped) | **YES** | 1.0000 (clipped) | 1.2068 | **YES** | No change (tied at ceiling) |
| after-exercise | 0.1582 | NO | 0.0729 | 0.0729 | NO | **Worse**, not recovered |

**Bar count: baseline 4/5 subjects >= 0.3, Landmark/KLT-ROI 2/5 subjects >= 0.3.**

**Does this recover the subject ABPF alone still misses?** No. after-exercise stays
below the 0.3 bar under Landmark/KLT-ROI, and its confidence is *lower* than the
ABPF-only baseline (0.0729 vs 0.1582), not higher.

**Does it change confidence on subjects ABPF already reached?** Yes, and the honest
answer is **regression** on 3 of the 4 subjects ABPF-only already had (5-gt, 6-gt fall
straight through the 0.3 floor down to ~0.01; 7-gt drops modestly but stays above the
bar), with only 12-gt unchanged (tied at the confidence-clip ceiling both conditions
already hit).

**Working hypothesis for why (documented as a hypothesis, not proven)**: the 0
dropped/fallback frames across every subject show the tracker technically succeeded --
it did not lose the ROI. But a per-frame similarity transform fit from sparse corner
features on a largely textureless forehead patch is itself a noisy estimate; even small
frame-to-frame registration jitter changes exactly which pixels get pooled into R/G/B
each frame, in a way uncorrelated with the true cardiac signal. ABPF's harmonic-comb
filter is a narrow, low-noise-tolerance operation -- exactly the kind of processing
step most sensitive to noise injected upstream of it. This would explain why the
subjects that regressed hardest (5-gt, 6-gt) are the ones where ABPF-only had the
*most* headroom to lose, and is consistent with Task C's tiling finding: a second,
independent ROI-stage modification that did not help and, here, measurably hurt this
specific fragile target.

## Action 4 — Drift sanity figure

`scripts/run_segment7_task_d_drift_sanity_figure.m`, subject `after-exercise` (chosen
for likely head movement, not the usual 5-gt figure-subject convention -- documented in
the script's own header). Renders `roi/landmarkROIExtraction.m`'s `debugFrame.samples`
on the 4 consecutive sample frames spanning the largest single-step face-bbox
displacement found across its 8 evenly-spaced samples, with the OLD axis-aligned
forehead box (yellow) and the NEW rotation-tracked polygon (green) drawn on the SAME
frames for direct comparison. Output:
`results/figures/segment7_task_d_drift_sanity_after-exercise.png`.

**What the figure actually shows**: across all 4 selected frames (spanning the largest
single-step face-bbox displacement found, 28.4 px), the yellow (old, axis-aligned) box
is essentially invisible underneath the green (new, tracked) polygon -- the two are
drawn at nearly identical positions and orientations. The subject's head barely
rotates in this window (there is a visible downward head tilt / eyes-closing
progression across the 4 frames, but that is mostly vertical translation of the face
box, not roll/rotation the tracked polygon would visibly compensate for). This is a
real, honest finding in its own right, flagged as a possibility in the script's own
header: little rotation happened in this clip for the tracker to visibly correct. It
is also consistent with the working hypothesis in Action 3 above -- the regression is
not explained by the tracked polygon swinging to some grossly wrong position (it
tracks almost exactly where the axis-aligned box already was), which supports
"per-frame jitter/registration noise" over "gross mistracking" as the more likely
mechanism.

## Action 5 — Regression check

SHA-256 hash comparison (this project's Segment 7 work is mostly uncommitted to git, so
a hash baseline was captured before any Task D edit rather than relying on `git diff`)
against every file this task's chain touches but must not modify:
`roi/extractROISignals.m`, `filtering/detrendSignal.m`,
`morphology/adaptiveHarmonicFilter.m`, `morphology/bandpassMorphology.m`,
`morphology/tiledROIExtraction.m`, `morphology/fixPolarityByGroundTruth.m`,
`morphology/fixPolarity.m`, `morphology/resampleUniform.m`,
`morphology/ensembleAverageBeats.m`, `morphology/extractMorphologyWaveform.m`,
`pulseextraction/chromCombine.m`, `heartrate/fftHeartRate.m`, `io/loadUBFCVideo.m`,
`io/loadGroundTruth.m`.

| Check | Result |
|---|---|
| All 14 files above, SHA-256 before vs. after | Identical, byte-for-byte |
| `morphology/notchDetectIEM.m` | Changed, but ONLY within `%`-comment lines (the header doc fix below) -- no executable line touched, confirmed by construction of the edit |

## One-line doc fix — `morphology/notchDetectIEM.m`

Per the handoff's instruction: the header comment describing Step 2's inflection-point
reading of the fetched IEM description has been checked against the primary source
(medRxiv 2024.03.05.24303735) and is confirmed correct. Updated from "ambiguous,
resolved by documented guess" to "verified against primary source, 2026-08-26" in both
the lead-in fidelity caveat and Step 2's own text. No logic changed.

## Task D2 — Testing the boundary-flicker hypothesis

Task D's leading hypothesis for WHY continuous-update Landmark/KLT-ROI regressed ABPF
so badly (stated up front, without re-deriving it here): `roi/extractROISignals.m`
only recomputes its ROI box at `detectEveryN=5` anchor frames and reuses it UNCHANGED
between anchors (`currentBBox = lastGoodBBox`) -- zero per-frame boundary movement
within a cycle. `roi/landmarkROIExtraction.m`'s original (continuous) mode instead
calls `estimateGeometricTransform2D` and `poly2mask` on EVERY frame, so even tiny
tracking noise flips a ring of boundary pixels in and out of the spatial mean every
single frame -- a noise source the fixed-box baseline structurally cannot have, and one
ABPF's narrow harmonic-comb filter is especially sensitive to. This action tests that
hypothesis directly.

### Action 1 — `freezeCadence` option

`roi/landmarkROIExtraction.m` gained an optional 3rd argument, `freezeCadence` (default
`false` -- the original, already-reported Task D behaviour, byte-for-byte unchanged
when omitted or explicitly `false`; verified below). When `true`, the tracked polygon
is still rotation-compensated (not a reversion to the axis-aligned baseline) but that
compensation is computed and applied ONLY once per `detectEveryN=5` cycle, at the
anchor frame -- resolving the whole previous cycle's net rotation in a single
`estimateGeometricTransform2D` call against the tracker's accumulated motion since the
last anchor -- and then held frozen, completely unchanged, for the up to 4 frames until
the next anchor. No `step()`/transform/`poly2mask` call happens on non-anchor frames in
this mode at all. See the function's own header (Step 2') for the full mechanism.

The `freezeCadence=false` code path was left 100% untouched (moved into its own
`elseif` branch, not edited) specifically so this new parameter carries zero risk to
the already-reported Task D result -- confirmed in Action 4 below.

### Action 2 — Batch script and results

`scripts/run_segment7_task_d2_frozen_cadence_batch.m`, identical to
`scripts/run_segment7_task_d_landmark_roi_batch.m` except
`landmarkROIExtraction(..., true)` in place of `landmarkROIExtraction(...)` -- same
shared-f0 source, same downstream ABPF chain, same everything else, so the cadence
variable alone is isolated between the two scripts' outputs.

`results/metrics/segment7_task_d2_frozen_cadence_notch.csv`, all 5 subjects, 0
failures, **0 dropped/fallback frames on every subject** (same as Task D's own
continuous-mode result -- again rules out "the tracker lost the ROI" as an explanation
for anything below).

### Action 3 — Three-way comparison table

| Subject | Baseline-ROI+ABPF | Continuous-tracking+ABPF | Frozen-cadence+ABPF | Frozen vs Continuous | Frozen vs Baseline |
|---|---|---|---|---|---|
| 5-gt | 0.7447 (**YES**) | 0.0127 (NO) | 0.0719 (NO) | Slightly better | Still far worse |
| 6-gt | 0.4120 (**YES**) | 0.0134 (NO) | 0.0668 (NO) | Slightly better | Still far worse |
| 7-gt | 0.6405 (**YES**) | 0.5937 (**YES**) | 0.0584 (NO) | **Much worse** | Much worse |
| 12-gt | 1.0000 (**YES**) | 1.0000 (**YES**) | 0.0126 (NO) | **Much worse** | Much worse |
| after-exercise | 0.1582 (NO) | 0.0729 (NO) | 0.0104 (NO) | Worse | Worse |

**Bar count (>=0.3): Baseline 4/5 -- Continuous-tracking 2/5 -- Frozen-cadence 0/5.**

Freezing the update cadence does not move confidence back toward baseline on ANY
subject in a way that matters -- and on 3 of the 5 subjects (7-gt, 12-gt,
after-exercise) it makes things measurably WORSE than the continuous-update condition
that was already regressed. The two subjects where freezing nudges confidence up over
continuous (5-gt: 0.0127->0.0719; 6-gt: 0.0134->0.0668) are trivial moves that stay two
orders of magnitude below baseline and nowhere near the 0.3 bar. Most strikingly,
**12-gt -- the one subject continuous-tracking left completely untouched, tied with
baseline at the 1.0000 confidence ceiling -- collapses to 0.0126 under frozen
cadence.** A mechanism that is supposed to REDUCE injected noise cannot explain making
an already-perfect-scoring subject catastrophically worse; something about the frozen
condition itself, not merely "less update noise", is driving this.

**Verdict, stated directly: the boundary-flicker hypothesis is RULED OUT**, not
confirmed and not partially confirmed in any sense that matters for practical
recovery. Reducing the update rate does not recover ABPF's lost confidence -- if
anything, the frozen condition is the WORST of the three tested (0/5 above the bar,
worse than continuous's 2/5). The two trivial upward nudges on 5-gt/6-gt are too small
and too inconsistent (7-gt and 12-gt move the opposite direction, hard) to count as
even partial confirmation of the specific mechanism proposed. **The true cause of Task
D's regression remains genuinely open** -- flagged here plainly rather than reached for
a second unverified guess. A plausible, un-tested alternative worth naming for whoever
picks this up next: the FROZEN polygon is only recomputed from a single one-shot
transform fit at the anchor (previous-anchor-points vs. new-anchor-tracked-points), so
any single bad point correspondence or partial occlusion at exactly that one frame now
corrupts the polygon for the ENTIRE next 5-frame cycle rather than being smoothed out
by the next frame's independent re-estimate (which is what continuous mode effectively
does) -- i.e., frozen cadence may have traded per-frame flicker noise for a DIFFERENT,
possibly worse failure mode (single-frame estimation error with no averaging-out and no
opportunity to self-correct until the next anchor). This is offered as a hypothesis for
a FUTURE task to test, not tested here.

### Action 4 — Regression check

**Default-path (`freezeCadence` omitted or `false`) byte-identical check**: reran
subject 5-gt through the full chain with the 3-arg call omitted (`landmarkROIExtraction(frames,
frameRate)`, exactly as `scripts/run_segment7_task_d_landmark_roi_batch.m` calls it)
after Action 1's edit and compared every downstream value against the exact,
already-reported Task D row:

| Field | Already-reported (Task D) | Re-run after Action 1 (default path) | Match |
|---|---|---|---|
| notchDetected | 1 | 1 | YES |
| notchPositionNormalized | 0.4392 | 0.4392 | YES |
| notchDepth | 0.1042 | 0.1042 | YES |
| confidence | 0.0127 | 0.0127 | YES |
| confidenceRaw | 0.0127 | 0.0127 | YES |
| hrBpmUsed | 76.4395 | 76.4395 | YES |
| beatsAveraged | 27 | 27 | YES |
| droppedFrameCount | 0 | 0 | YES |
| numFrames | 2409 | 2409 | YES |

**PASS, exact match on every field.** This was checked directly for 5-gt only (not
re-run for all 5 subjects, to avoid another multi-hour batch run purely to re-confirm
determinism); the other 4 subjects are not independently re-verified by execution, but
the `freezeCadence=false` code path is the SAME code (moved into an `elseif` branch,
not edited or reordered -- see Action 1) executing on deterministic MATLAB functions
(Viola-Jones detection, `detectMinEigenFeatures`, `vision.PointTracker`,
`estimateGeometricTransform2D` all confirmed to reproduce identical output on identical
input here), so byte-identical output for the other 4 subjects follows by construction,
not by additional measurement.

**Protected-file hash check**: SHA-256 hashes of every file this task's chain touches
but must not modify (`roi/extractROISignals.m`, `filtering/detrendSignal.m`,
`morphology/adaptiveHarmonicFilter.m`, `morphology/bandpassMorphology.m`,
`morphology/tiledROIExtraction.m`, `morphology/fixPolarityByGroundTruth.m`,
`morphology/fixPolarity.m`, `morphology/resampleUniform.m`,
`morphology/ensembleAverageBeats.m`, `morphology/extractMorphologyWaveform.m`,
`pulseextraction/chromCombine.m`, `heartrate/fftHeartRate.m`, `io/loadUBFCVideo.m`,
`io/loadGroundTruth.m`) compared against their end-of-Task-D baseline: **identical,
byte-for-byte, all 14 files.** `morphology/notchDetectIEM.m` was not opened or edited
in Task D2 at all (confirmed by session log -- no Edit/Write call against it since Task
D's own one-line doc fix).

## Repo-convention note

The handoff's brief referred to this doc's path as `docs/Segment7_Task_D_Landmark_ROI.md`.
Every prior Segment 6/7 per-task write-up (K/L/N/O/P/Q/R, Task A, Task B) actually lives
under `matlab/docs/`, per `README.md`'s own documented folder structure (`docs/` at the
repo root is for cross-cutting project documentation -- `DATA_FORMAT.md`,
VIPL/Hoffman notes, the Android port spec -- not per-task write-ups). This doc follows
the real, established convention (`matlab/docs/Segment7_Task_D_Landmark_ROI.md`) rather
than the brief's literal path, consistent with every task before it in this series.

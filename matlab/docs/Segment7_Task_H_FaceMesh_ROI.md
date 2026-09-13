# Segment 7 Task H — Real DL Face-Mesh ROI

Continues Segment 7 Task D (`Segment7_Task_D_Landmark_ROI.md`, read first; nothing already
established there is re-derived here). Task D's Action 0 found no facial-landmark/face-mesh
detector anywhere in this MATLAB R2024b installation and fell back to a KLT-tracked
rotation-compensation proxy, which regressed ABPF's notch confidence (baseline 4/5 subjects
above the 0.3 confidence bar → 2/5 under continuous tracking → 0/5 under frozen cadence). The
supervisor has now explicitly authorized using a real deep-learning face-mesh model for face
detection, closing the "no toolbox exists" premise Task D's fallback was built on.

## Action 0 — Feasibility: can MATLAB actually call a real face-mesh model here?

MATLAB itself still ships no face-mesh function (unchanged from Task D's finding). But
MATLAB R2024b supports calling out to Python (`py.*`), and Google's **MediaPipe FaceMesh** —
a real, published, deep-learning 468-point face-mesh model — is installable from PyPI. Its
landmark indexing is very likely what the uploaded thesis's Section 3.2.1 is built on: indices
67, 297, 105, 334 only make sense under MediaPipe's specific 468-point topology, which is
presumably why this project's own docs already described "a 468-point face mesh" using those
exact numbers before this task existed.

Checked directly, in order, before writing any pipeline code:

1. **Internet/PyPI access**: available. `pip index versions mediapipe` succeeded.
2. **mediapipe 1.0.1** (latest): installs, but removed the legacy `mediapipe.solutions.face_mesh`
   API in favor of a Tasks API that requires downloading a separate `.task` model asset.
   Switched to **mediapipe 0.10.21**, which still ships the self-contained legacy API (model
   bundled in the package, no separate download) — this is the version actually used.
3. **In-process Python call from MATLAB** (`pyenv` default `ExecutionMode: InProcess`):
   **crashes** — `ImportError: DLL load failed while importing _framework_bindings`. This is a
   native-library conflict between MATLAB's own bundled DLLs and mediapipe's compiled C++
   bindings when loaded into the same process.
4. **Out-of-process Python call** (`pyenv('ExecutionMode', 'OutOfProcess')`, which must be set
   BEFORE any other `py.*` call in the session — it cannot be changed once Python is loaded):
   **works**. Verified against a real UBFC frame (subject 5-gt) before writing
   `roi/faceMeshROIExtraction.m`: real face detected, all 468 landmarks returned, landmarks 67/
   297/105/334 at plausible pixel coordinates.
5. **Protobuf field access quirk**: MATLAB's `py.*` dot-property resolution doesn't find
   mediapipe's protobuf-generated `.landmark` field directly (`Unrecognized method, property,
   or field 'landmark'`) — fixed by using `py.getattr(obj, 'landmark')` to force Python-level
   attribute lookup instead of MATLAB's own introspection.

**Conclusion: feasible, via `pyenv('ExecutionMode','OutOfProcess')` + mediapipe 0.10.21's
legacy `solutions.face_mesh` API + `py.getattr` for protobuf fields.** This is a real,
published DL model doing real inference (confirmed via `TensorFlow Lite XNNPACK delegate`
initialization in the log output), not a stand-in.

## Action 1 — `roi/faceMeshROIExtraction.m`

New file, additive, in `roi/` (same stage-based convention as `extractROISignals.m` and
`landmarkROIExtraction.m`). Returns raw, per-channel `R`, `G`, `B` — same shape/convention as
both prior ROI functions, so it is a direct drop-in for the same ABPF-chain comparison Task D
already established.

**Landmark geometry**: the thesis's own listed order (67, 297, 105, 334) does not trace a
simple (non-self-intersecting) polygon — 105 and 297 are diagonal from each other, not
adjacent, so connecting the 4 points in that literal order would bowtie. Checked directly
against real pixel coordinates on a UBFC frame: landmarks 67/105 sit on one side of the
forehead (67 above 105), 297/334 on the other (297 above 334). The polygon vertex order used
is **[67, 297, 334, 105]** — a proper clockwise loop (upper-side-A → upper-side-B →
lower-side-B → lower-side-A). This re-orders the same 4 landmarks into a valid polygon; it
does not change which landmarks are used.

**Detection cadence**: unlike `extractROISignals.m`'s every-5th-frame Viola-Jones cadence,
this calls MediaPipe FaceMesh on **every frame**, with `static_image_mode=false` (MediaPipe's
own internal temporal tracking, not re-detection from scratch each call) — both for landmark
stability across frames and because per-frame cost is tolerable (see runtime note below).
Falls back to the last good polygon if no face is detected in a given frame; a centered
fallback polygon is used if no detection has ever succeeded yet — same "last-known-good"
philosophy as `extractROISignals.m` and `landmarkROIExtraction.m`.

**Runtime**: measured ~0.26 s/frame on this machine (smoke-tested on a 150-frame clip before
the full batch — see the debug figure showing the polygon precisely on the forehead, right
above the eyebrows, well inside the hairline). This is slower than the ~0.047 s/frame measured
in an isolated Python-only timing test — the difference is attributed to the added cost of
`py.numpy.array()` marshalling a ~640×480×3 frame across the out-of-process boundary for every
single call, plus MATLAB's own per-call `py.*` overhead, both intrinsic to `OutOfProcess` mode
(the only mode that doesn't crash here — see Action 0). At this rate, a ~2400-frame UBFC
subject takes roughly 10 minutes.

## Action 2 — Batch script and results

`scripts/run_segment7_task_h_facemesh_roi_batch.m`, same protocol as
`scripts/run_segment7_task_d_landmark_roi_batch.m`: same 5 UBFC subjects, same shared-f0
source (the existing baseline `extractROISignals.m` decode, not a fresh estimate from the
face-mesh ROI's own traces, so both conditions are compared at the same f0 operating point),
same ABPF chain at the same pipeline position, same CSV columns.

`results/metrics/segment7_task_h_facemesh_notch.csv` — see the table below.

## Action 3 — Comparison table: Baseline vs Landmark/KLT (Task D) vs Face-Mesh (Task H)

All 5 subjects succeeded, 0 dropped/no-face frames on ANY subject for the face-mesh condition
(MediaPipe FaceMesh found a face on literally every single frame across all 5 videos) — the
detector itself is robust; this is not an "it kept losing the face" story, same as Task D's
own KLT proxy having 0 fallback frames too. All three conditions share the identical f0
operating point (Step 1's baseline-derived `sharedF0Hz`), so `hrBpmUsed` is near-identical
across all three (e.g. 5-gt: 76.41-76.44 bpm in every condition) — only the ROI stage differs.

| Subject | Baseline (axis-aligned box) | Landmark/KLT proxy (Task D) | **Real face-mesh (Task H)** |
|---|---|---|---|
| 5-gt | 0.7447 (**YES**) | 0.0127 (NO) | 0.0505 (NO) |
| 6-gt | 0.4120 (**YES**) | 0.0134 (NO) | 0.0740 (NO) |
| 7-gt | 0.6405 (**YES**) | 0.5937 (**YES**) | 0.0603 (NO) |
| 12-gt | 1.0000 (**YES**, clipped) | 1.0000 (**YES**, clipped) | 0.1940 (NO) |
| after-exercise | 0.1582 (NO) | 0.0729 (NO) | **0.2323 (NO, but the best any condition has scored this subject)** |

**Bar count (>= 0.3): Baseline 4/5 — Landmark/KLT 2/5 — Real face-mesh 0/5.**

**Verdict, stated directly: this is also a negative result, and by subject count it is the
worst of the three ROI variants tried across Segment 7 (Task C's tiling, Task D's KLT proxy,
this task's real face-mesh).** A real, precisely-anatomically-placed, deep-learning-detected
landmark ROI does NOT recover ABPF's notch confidence — if anything it drops further below the
KLT proxy on 3 of 5 subjects (5-gt, 6-gt, 7-gt), ties roughly with KLT on 12-gt (both collapse
from baseline's near-1.0/1.0 down into the 0.02-0.19 range), and is the only condition to beat
every prior score on after-exercise (0.2323 vs baseline's 0.1582 and KLT's 0.0729) — a genuine
small win on the one subject nothing else has cracked, but not enough to change the overall
verdict, and not itself confident.

**Working hypothesis for why (documented as a hypothesis, consistent with and extending Task
D's own working hypothesis, not proven)**: the face-mesh polygon is visibly, substantially
SMALLER than the axis-aligned baseline box — a precise strip just above the eyebrows and below
the hairline (see the debug figure saved for each subject,
`results/figures/segment7_task_h_facemesh_<subjectID>.png`), versus the baseline's more
generous `x:[0.30,0.70] y:[0.10,0.30]` face-fraction box. Fewer pooled pixels means a noisier
per-frame spatial average (sensor/quantization noise falls off as 1/sqrt(pixel count));
ABPF's narrow harmonic-comb filter has already been shown (Segment 7 Task E, and every prior
Task C/D result) to have very low tolerance for noise injected upstream of it. This would mean
the SAME anatomical precision that makes this ROI "more correct" per the thesis is, for THIS
specific narrow-band notch-detection pipeline, actively counterproductive — trading placement
accuracy for pixel count, when this pipeline's real bottleneck is pixel count (SNR), not
placement accuracy. This is now the THIRD independent ROI-stage change in this project (Task
C's tiling, Task D's KLT tracking, this task's real landmarks) to fail to help this specific
target, each for a plausibly different upstream-noise-sensitivity reason -- while the
production HR path (Branch 1, wide 0.7-4 Hz band, no harmonic comb) is comparatively tolerant
of ROI-stage changes and would need its own separate before/after comparison to know whether
face-mesh ROI helps or hurts THAT path (not tested in this task -- Task H targeted the same
notch-confidence question Task D asked, for a direct apples-to-apples comparison; a
Branch-1-only comparison is a natural, cheap follow-up since it does not require re-running
ABPF or the beat-averaging chain at all).

**What this means for "the mesh will make our rPPG more accurate/noise-free" as a claim to a
reviewer**: it does not, for the notch/morphology branch, on this evidence. Task I (below)
answers the Branch 1 follow-up this left open.

## Task I — Does face-mesh ROI change Branch 1 (production HR)?

`scripts/run_segment7_task_i_facemesh_branch1_batch.m`. Same 5 subjects, same face-mesh
decode approach (cached this time to `data/processed/<subjectID>_facemesh_rgb_traces.mat`
so it doesn't need re-running), fed through the UNCHANGED, unmodified Branch 1 sequence
(`detrendSignal` -> `bandpassClean` -> `chromCombine`/`posCombine` -> `fftHeartRate`) exactly
as `scripts/run_segment4_heartrate_batch.m` does, compared against the same subjects'
already-cached baseline ROI traces.

`results/metrics/segment7_task_i_facemesh_branch1_hr.csv`:

| Subject | Ground truth | HR_chrom baseline | HR_chrom face-mesh | HR_pos baseline | HR_pos face-mesh | Error (either ROI) |
|---|---|---|---|---|---|---|
| 5-gt | 77.32 | 76.41 | **76.41** | 76.41 | **76.41** | 0.91 |
| 6-gt | 82.59 | 83.02 | **83.02** | 83.02 | **83.02** | 0.43 |
| 7-gt | 94.69 | 91.77 | **91.77** | 91.77 | **91.77** | 2.92 |
| 12-gt | 94.57 | 95.81 | **95.81** | 95.81 | **95.81** | 1.25 |
| after-exercise | 113.86 | 100.50 | **100.50** | 100.50 | **100.50** | 13.35 |

**Result: HR_chrom and HR_pos are bit-for-bit identical between the baseline ROI and the
real face-mesh ROI on EVERY subject** — same bpm to 4 decimal places, same absolute error
against ground truth, on all 5 subjects, both metrics. Only the never-shipped, uncombined
green-only metric (not part of this project's reported HR result) differs meaningfully on
some subjects (e.g. 7-gt: 95.41 baseline vs 67.73 face-mesh).

**Interpretation**: this is not a coincidence at this consistency (5/5 subjects, 2/2 metrics,
exact bit-for-bit match) — it directly confirms Task H's own working hypothesis from the
other direction. `fftHeartRate.m`'s peak-frequency-pick only needs the cardiac fundamental to
be the DOMINANT frequency inside the 0.7-4 Hz band; CHROM/POS's whole point is to project out
motion/noise and enhance exactly that dominant component. Both the baseline's generous box and
the face-mesh's precise, smaller region capture the same true underlying cardiac signal well
enough for that peak to land on the identical FFT bin either way — Branch 1 is simply
insensitive to which reasonable forehead sub-region feeds it, unlike Branch 2's narrow
harmonic comb.

**Bottom line across Tasks H and I together**: the real face-mesh ROI is a genuine engineering
success (a real DL model, precisely placed, zero detection failures across all 5 subjects,
both tasks) that changes **nothing** for the reported HR metric (bit-identical) and makes
Branch 2's notch confidence **worse**, not better. There is no result in this project, on this
evidence, where switching to the face-mesh ROI is the right call over the simple baseline box.


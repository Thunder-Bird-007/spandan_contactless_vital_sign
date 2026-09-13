# Segment 7 Task J — Face-Mesh Hybrid ROI (Detection + Baseline Box Geometry)

Continues Segment 7 Tasks H and I (`Segment7_Task_H_FaceMesh_ROI.md` — Task I's own
findings are a section inside that same doc, not a separate file; read the whole thing
first, nothing already established there is re-derived here). Task H built
`roi/faceMeshROIExtraction.m`, a real 468-point
MediaPipe FaceMesh ROI using the uploaded thesis's exact landmark indices (67, 297,
105, 334), and found it has zero dropped frames across all 5 UBFC test subjects but
**regresses** ABPF's dicrotic-notch confidence hard: 0/5 subjects above the 0.3 bar,
worse than both the axis-aligned baseline box (4/5) and Task D's KLT-tracked proxy
(2/5). Task I then confirmed the same face-mesh ROI ties baseline **bit-for-bit** on
the production HR path (Branch 1: CHROM/POS + `fftHeartRate.m`), on all 5 subjects,
both metrics. Task H's working hypothesis for the notch regression: the 4-landmark
polygon is a thin strip hugging the eyebrows, pooling far fewer pixels than baseline's
generous `x:[0.30,0.70] y:[0.10,0.30]` forehead box, which raises per-frame spatial
average noise (noise falls off as 1/sqrt(pixel count)) — and ABPF's narrow
harmonic-comb filter has already been shown, repeatedly, to have very low tolerance for
noise injected upstream of it.

**This task's question, stated up front**: is Task H's regression really about pixel
count (ROI *shape*), or could it instead be about *something else* correlated with
switching to the face-mesh path — e.g. per-frame Python round-trip jitter, or a subtly
different effective sampling of the face? Task J isolates these by combining real
face-mesh **detection/localization** with baseline's own **box geometry and pixel
count** — if the hybrid recovers baseline's notch confidence, Task H's pixel-count
hypothesis is confirmed; if it doesn't, something else about the face-mesh path is
responsible and the working hypothesis needs revision.

**Bottom line, stated up front**: the hybrid ROI is a **partial, not a full, confirmation**
of Task H's pixel-count hypothesis, and by pass count it is **still a negative result**.
Swapping the thin 4-landmark polygon for a real forehead-box-sized rectangle (same
face-mesh detector, same pixel-pooling area as baseline) recovers notch confidence on
**1/5** subjects above the 0.3 bar — an improvement over the pure face-mesh polygon's
0/5, consistent with pixel count mattering, but nowhere close to baseline's 4/5, and
actually **below** Task D's KLT proxy (2/5). HR parity, however, is confirmed again:
Branch 1 (`HR_chrom`/`HR_pos`) is bit-for-bit identical to baseline on all 5 subjects,
exactly as Task I found for the thin-polygon face-mesh ROI. See the Verdict section for
the full interpretation.

## Action 1 — `roi/faceMeshHybridROIExtraction.m`

New file, same `[R, G, B, roiTimestamps, droppedFrameIdx, debugFrame]` signature and
output convention as `roi/faceMeshROIExtraction.m` (Task H). Reuses Task H's mediapipe
setup and per-frame detection loop as-is — same `pyenv('ExecutionMode', 'OutOfProcess')`
requirement, same `py.getattr` protobuf-object access pattern, same reuse-last-known /
centered-fallback pattern for frames where MediaPipe finds no face. The one change is
what happens on a successful detection:

- Instead of reading only the 4 thesis-specified landmarks (67, 297, 105, 334) to build
  a thin `poly2mask` polygon, **all 468** returned landmarks' pixel coordinates are read
  and their axis-aligned bounding box is taken as the face-scale reference for that
  frame: `faceBBox = [min_x, min_y, max_x-min_x, max_y-min_y]`.
- `roi/extractROISignals.m`'s exact default forehead fractions —
  `xFracLo=0.30, xFracHi=0.70, yFracLo=0.10, yFracHi=0.30` (its `computeRegionBBoxes` /
  `clampedBBox`, copied verbatim, not re-derived or re-tuned) — are applied to that
  bbox to get a rectangular ROI.
- Pixels inside that rectangle are averaged with plain slicing
  (`img(y1:y2, x1:x2, :)`), the same mechanism `extractROISignals.m` uses, **not**
  `poly2mask` — there is no longer a polygon to rasterize, the ROI is already an
  axis-aligned rectangle.

`debugFrame` carries `image` / `faceBBox` / `roiBBox` / `frameIndex` — matching
`extractROISignals.m`'s field names (not Task H's `faceMeshLandmarksPx` /
`roiPolygon`), so the existing `insertObjectAnnotation`-based sanity-PNG drawing code
(`scripts/run_segment2_roi_batch.m`'s pattern) works unchanged.

Does **not** modify `roi/faceMeshROIExtraction.m`, `roi/extractROISignals.m`, or
`roi/landmarkROIExtraction.m` — new, additive file only.

**Implementation note (bug found and fixed before any usable run completed)**: the
first version of the landmark-extraction loop read each of the 468 landmarks' `x`/`y`
with a MATLAB-side loop calling `landmarkList{k}` + `py.getattr(pt, 'x'/'y')` per
landmark — 936 separate MATLAB↔Python round trips per frame under `pyenv`
`OutOfProcess` mode (vs. Task H's own loop, which only ever does this 8 times/frame for
4 landmarks). Across a ~2400-frame subject this leaked proxy-object handles badly
enough that the first live batch run failed one subject with
`MATLAB:Python:DispatchError` ("Attempting to access the property or method of an
invalid object"), then crashed MATLAB entirely on the next subject (Windows exit
`0xc00000fd`, stack overflow, preceded by an "Out of memory" message from the Python
bridge). Fixed by replacing the per-landmark loop with a single batched Python-side
list comprehension per frame (`py.eval('[[p.x, p.y] for p in lm]', ...)`, converted to
a numpy array and pulled back as one MATLAB double array) — this keeps the round-trip
count per frame small and constant regardless of landmark count. Re-verified in
isolation against a synthetic `types.SimpleNamespace` landmark list before rerunning
the full batches; both batches below ran to completion with 0 failures and 0 dropped
frames on the fixed version.

## Action 2 — Notch-confidence batch: `scripts/run_segment7_task_j_facemesh_hybrid_roi_batch.m`

Duplicate of `scripts/run_segment7_task_h_facemesh_roi_batch.m` with the ROI call
swapped to `faceMeshHybridROIExtraction.m` — no other methodology changes: same 5 UBFC
subjects (5-gt, 6-gt, 7-gt, 12-gt, after-exercise), same shared-f0 source (baseline
`extractROISignals.m`'s own whole-ROI wide-band CHROM decode, **not** a fresh estimate
from the hybrid ROI's own traces — keeps all conditions compared at the same f0
operating point), same ABPF (`adaptiveHarmonicFilter.m`, order 6) chain position, same
tail (`fixPolarityByGroundTruth.m` → `resampleUniform.m` → `ensembleAverageBeats.m` →
`notchDetectIEM.m`), same CSV columns.

Output: `results/metrics/segment7_task_j_facemesh_hybrid_notch.csv`.

### Per-subject notch-confidence table — all four ROI methods

Baseline column is the doc-quoted values from `docs/Segment7_Task_H_FaceMesh_ROI.md`'s
own comparison table (same source Task H/I used); KLT and real-face-mesh columns from
`results/metrics/segment7_task_d_landmark_notch.csv` and
`.../segment7_task_h_facemesh_notch.csv` respectively; Hybrid column read verbatim from
`results/metrics/segment7_task_j_facemesh_hybrid_notch.csv` (this task, 0 failures, 0
dropped frames on all 5 subjects).

| Subject | Baseline (axis-aligned box) | Landmark/KLT proxy (Task D) | Real face-mesh polygon (Task H) | **Hybrid: mesh-detect + box-geometry (Task J)** |
|---|---|---|---|---|
| 5-gt | 0.7447 (YES) | 0.0127 (NO) | 0.0505 (NO) | 0.2569 (NO) |
| 6-gt | 0.4120 (YES) | 0.0134 (NO) | 0.0740 (NO) | **0.4544 (YES)** |
| 7-gt | 0.6405 (YES) | 0.5937 (YES) | 0.0603 (NO) | 0.0208 (NO) |
| 12-gt | 1.0000 (YES, clipped) | 1.0000 (YES, clipped) | 0.1940 (NO) | 0.1491 (NO) |
| after-exercise | 0.1582 (NO) | 0.0729 (NO) | 0.2323 (NO) | 0.0192 (NO) |

**Bar count (>= 0.3): Baseline 4/5 — Landmark/KLT 2/5 — Real face-mesh 0/5 —
Hybrid 1/5.**

The hybrid recovers exactly one subject (6-gt) above the bar — and on that subject it
actually edges out baseline itself (0.4544 vs. 0.4120). But it does **not** come close
to closing the gap to baseline's 4/5: three of baseline's four passing subjects (5-gt,
7-gt, 12-gt) still fail under the hybrid, two of them by a wide margin (7-gt collapses
from 0.6405 to 0.0208; 12-gt from a clipped 1.0000 to 0.1491). It also lands **below**
Task D's KLT proxy (1/5 vs. 2/5), the worst-performing prior ROI-stage intervention in
this project besides the pure face-mesh polygon itself.

**Interpretation relative to Task H's pixel-count hypothesis**: this is a **partial
confirmation, not a full one**. Giving the hybrid the same pooled pixel area as baseline
did measurably help relative to the thin polygon (0/5 → 1/5, and 6-gt's confidence more
than doubled from 0.0740 to 0.4544) — consistent with pixel count being part of the
story. But if pixel count were the *whole* story, the hybrid should have landed at or
near baseline's 4/5, since it uses baseline's exact box geometry; instead most subjects
still land far below baseline (5-gt, 7-gt, 12-gt, after-exercise all still fail, several
by a large margin). Something else tied to the face-mesh detection/localization path
itself — not just how many pixels get pooled — is still costing confidence on most
subjects. This experiment narrows the explanation (pixel count is A factor) without
fully resolving it (it is not the ONLY factor).

## Action 3 — Branch-1 HR-parity batch: `scripts/run_segment7_task_j_facemesh_hybrid_branch1_batch.m`

Duplicate of `scripts/run_segment7_task_i_facemesh_branch1_batch.m` with the ROI call
swapped to `faceMeshHybridROIExtraction.m` — same 5 subjects, same Branch 1 sequence
(`detrendSignal` → `bandpassClean` → `chromCombine`/`posCombine` → `fftHeartRate`,
unchanged), same ground-truth windowing convention. Raw hybrid R/G/B traces are cached
to `data/processed/<subjectID>_facemesh_hybrid_rgb_traces.mat` (new filename, doesn't
collide with baseline's `<subjectID>_rgb_traces.mat` or Task I's
`<subjectID>_facemesh_rgb_traces.mat`).

Output: `results/metrics/segment7_task_j_facemesh_hybrid_branch1_hr.csv`.

### HR parity result

Read verbatim from `results/metrics/segment7_task_j_facemesh_hybrid_branch1_hr.csv`
(0 failures, 0 dropped frames on all 5 subjects).

| Subject | Ground truth | HR_chrom baseline | HR_chrom hybrid | HR_pos baseline | HR_pos hybrid | Error (either ROI) |
|---|---|---|---|---|---|---|
| 5-gt | 77.32 | 76.4105 | **76.4105** | 76.4105 | **76.4105** | 0.91 |
| 6-gt | 82.59 | 83.0194 | **83.0194** | 83.0194 | **83.0194** | 0.43 |
| 7-gt | 94.69 | 91.7691 | **91.7691** | 91.7691 | **91.7691** | 2.92 |
| 12-gt | 94.57 | 95.8128 | **95.8128** | 95.8128 | **95.8128** | 1.25 |
| after-exercise | 113.86 | 100.5034 | **100.5034** | 100.5034 | **100.5034** | 13.35 |

**Result: HR_chrom and HR_pos are bit-for-bit identical between baseline and the
hybrid ROI on every subject** — same bpm to 4 decimal places, same absolute error
against ground truth, all 5 subjects, both metrics. Exactly the same outcome Task I
found for the thin-polygon face-mesh ROI. Only the never-shipped, uncombined
green-only metric differs on some subjects (e.g. 6-gt: 65.69 baseline vs. 85.19 hybrid;
7-gt: 95.41 baseline vs. 65.55 hybrid; after-exercise: 75.51 baseline vs. 103.56
hybrid) — not part of this project's reported HR result, and consistent with Task I's
own finding that CHROM/POS's noise-rejection makes Branch 1 insensitive to which
reasonable forehead-region ROI feeds it, unlike Branch 2's narrow ABPF comb.

## Verdict

Task J's isolation experiment gives a **mixed, still-net-negative** answer. It
confirms detector-robustness was never the problem (0 dropped frames, as in Task H),
and it confirms Task H/I's HR-branch finding is genuinely ROI-shape-independent (bit-
identical CHROM/POS on all 5 subjects again). On the notch-confidence question it
specifically came to answer, it shows Task H's pixel-count hypothesis is **real but
incomplete**: restoring baseline's pixel-pooling area to the face-mesh path recovers
one subject (0/5 → 1/5, and a genuine, if narrow, win over baseline on 6-gt) but does
not come close to closing the gap to baseline's 4/5, and it under-performs even Task
D's KLT proxy (2/5). Ranked by notch pass count across every ROI-stage experiment in
Segment 7: **Baseline (4/5) > KLT proxy (2/5) > Hybrid mesh-detect+box-geometry (1/5)
> Real face-mesh polygon (0/5)**.

**Practical takeaway**: there is still no ROI variant in this project, mesh-based or
otherwise, that beats the simple axis-aligned Viola-Jones box on the notch-confidence
target — the hybrid is a smaller loss than the pure face-mesh polygon, not a win. Since
pixel count only explains part of the regression, whatever the face-mesh detection path
is doing beyond ROI shape (e.g. per-frame localization jitter from a fresh
per-frame detection vs. baseline's every-5th-frame-then-hold cadence, or some other
difference in exactly which pixels a mesh-derived box selects frame-to-frame even at
matched size) remains unidentified and would need a further, narrower experiment to
isolate — not attempted here, and not a hypothesis this task's evidence can adjudicate
between. For both the reported HR metric and the notch-confidence metric, the
axis-aligned baseline box remains the right choice on this project's evidence.

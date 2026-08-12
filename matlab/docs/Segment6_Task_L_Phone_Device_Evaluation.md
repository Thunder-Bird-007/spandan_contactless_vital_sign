# Segment 6, Task L — Phone (source2) Device-Generalization Evaluation

This is an additional task, run alongside (not replacing) `Segment6_Refinement_Notes.md`
and the Task K v7-integration work already in place. It answers a specific
demo-day risk this project's own notes already flagged: the Android app will
be hand-held on a phone's FRONT camera, and until this pass the validated
CHROM/POS/switching pipeline had only ever been evaluated on webcam
(source1) footage at any real scale. This is a device-generalization check,
not a range-strengthening exercise like the earlier v7 work — the question
is "does the pipeline hold up on real phone-camera footage," not "does more
data improve the fit."

No pipeline function was modified. `extractROISignals.m`, `detrendSignal.m`,
`bandpassClean.m`, `chromCombine.m`, `posCombine.m`, `fftHeartRate.m`,
`ratioOfRatios.m`, and `calibrateSpO2.m` are all used completely unmodified.
Only new I/O/batch scripts were added: `run_vipl_phone_v1_batch.m`,
`run_vipl_phone_v8v9_batch.m`, and `run_vipl_device_stratified_eval.m`.

## 1. Extraction (Actions 1-2)

Source2 (HUAWEI P9 phone) video was extracted from the 21 VIPL-HR zip
archives for v1, v8, and v9, skipping any subject/scenario/file already
present on disk. 1220 new files were extracted, 52 were skipped as
already-present (the pre-existing p1 + p84/p97-p107 fallback-set v1/source2
raw video).

| Scenario | Videos on disk after extraction | Expected (archive coverage, `VIPL_Scenario_Coverage.md`) | Match |
|---|---|---|---|
| v1/source2 | 107/107 | 107/107 | exact |
| v8/source2 | 106/107 | 106/107 | exact |
| v9/source2 | 105/107 | 105/107 | exact |

v8/v9 (Action 1) were prioritized first as specified, since they are the
only VIPL-HR scenarios where the subject actually holds the phone
("video chat scenario" per the dataset authors) — the closest physical
match to how the Android app will be used at defense. v1 (Action 2) fills
out full-pool phone-camera coverage for the fixed-camera baseline scenario:
previously only 13 of 107 subjects (p1 + the 12 source1-fallback subjects)
had v1/source2 raw video on disk at all.

## 2. Segment 2-5 processing (Action 3)

`run_vipl_phone_v1_batch.m` and `run_vipl_phone_v8v9_batch.m` ran the full,
unmodified Segment 2-5 pipeline against every extracted video, with a
mandatory ROI + filtering + HR sanity PNG per subject.

| Batch | Subjects attempted | Not extracted (skipped, not a failure) | Processing failures |
|---|---|---|---|
| v1/source2 | 107 | 0 | 0 |
| v8/source2 + v9/source2 | 211 | 3 (p56/v8, p45/v9, p56/v9) | 0 |

The 3 not-extracted combinations exactly match `Missing_data.txt`'s
already-documented gaps (p56 is missing v6 through v9 entirely; p45 is
missing v9 only) — no new gap was introduced by this pass. Every video that
was extracted was successfully processed through the full pipeline; there
were zero hard pipeline failures (no crashes, no corrupt-video errors) on
either batch.

### Face-detection difficulty on hand-held footage (anticipated finding)

Per the Task L brief, hand-held motion blur and framing drift were expected
to make Viola-Jones face detection genuinely harder for v8/v9 than for any
fixed-camera scenario already in this pipeline. This is confirmed, not as a
bug but as a real, measurable, and — relative to the effect on HR accuracy
below — fairly modest effect:

- **v1 (fixed phone-on-stand):** 197 dropped/reused-bbox frames out of
  107,396 total frames processed = **0.18%**.
- **v8+v9 (hand-held) pooled:** 2504 dropped/reused-bbox frames out of
  209,450 total frames processed = **1.20%** — roughly **6.6x** the
  fixed-camera rate.

Most v8/v9 subjects still land under 5% dropped frames, but a handful show
severe, sustained detection loss, worth flagging explicitly rather than
averaging away:

| Subject/scenario | Dropped/reused-bbox frames | % of clip |
|---|---|---|
| VIPL_p23_v9_source2 | 446 / 918 | **48.6%** |
| VIPL_p27_v9_source2 | 272 / 1441 | 18.9% |
| VIPL_p50_v8_source2 | 119 / 944 | 12.6% |
| VIPL_p29_v9_source2 | 125 / 1011 | 12.4% |
| VIPL_p29_v8_source2 | 137 / 1143 | 12.0% |
| VIPL_p53_v9_source2 | 148 / 1359 | 10.9% |
| VIPL_p90_v9_source2 | 93 / 984 | 9.5% |
| VIPL_p89_v9_source2 | 79 / 937 | 8.4% |

p23_v9 in particular lost the face for nearly half the clip and reused a
stale bounding box for that entire span — its HR estimate should be treated
as unreliable rather than a genuine pipeline failure on this subject. The
corresponding ROI sanity PNGs (`results/figures/VIPL_p23_v9_source2_roi_sanity.png`
etc.) show why: fast hand-and-head motion together pushes the face out of
frame or into heavy blur for extended stretches, which `extractROISignals.m`
was never designed to recover from mid-clip (by design — it was left
unmodified, per this task's constraints).

## 3. Device-stratified HR evaluation (Action 4)

`run_vipl_device_stratified_eval.m` pooled every processed VIPL
`*_hr_estimates.mat` file (519 total, all NaN-free) and computed MAE/RMSE/r
for CHROM, POS, and the Task J switching estimator (29.27% relative-
disagreement threshold), grouped by source device and scenario. Full table
saved at `results/metrics/segment6_device_stratified_hr_metrics.csv`.

**source3 (RealSense) has never been extracted or processed anywhere in
this pipeline** — the device-stratified comparison below is source1
(webcam) vs source2 (phone) only. This is a pre-existing gap in the
project, not something Task L introduced.

| Group | n | MAE (chrom) | MAE (pos) | MAE (switched) | r (switched) |
|---|---|---|---|---|---|
| source1, pooled (webcam) | 186 | 10.85 | 10.07 | 10.40 | 0.490 |
| source2, pooled (phone) | 333 | 15.76 | 16.73 | 16.28 | 0.174 |
| source1, v1 | 95 | 8.07 | 8.08 | 7.77 | 0.290 |
| source2, v1 | 107 | 15.75 | 16.35 | 15.60 | 0.035 |
| source1, v7 | 91 | 13.75 | 12.14 | 13.14 | 0.528 |
| source2, v7 | 15 | 27.24 | 26.60 | 26.03 | 0.177 |
| source2, v8 (hand-held, stable) | 106 | 14.62 | 16.78 | 16.48 | 0.073 |
| source2, v9 (hand-held, motion) | 105 | 15.27 | 15.66 | 15.37 | 0.214 |
| **v1 phone vs v1 webcam, same scenario** | 107 vs 95 | 15.75 vs 8.07 | 16.35 vs 8.08 | 15.60 vs 7.77 | 0.035 vs 0.290 |
| **v8+v9 pooled (hand-held)** | 211 | 14.94 | 16.22 | 15.93 | 0.137 |

### Bottom line: the phone gap is real, and it is a device effect, not a
### hand-held-motion effect

**The demo-day risk this project's own notes flagged ("the phone is a
camera the calibration has never seen") is confirmed by real data.** Pooled
across every scenario, source2 (phone) MAE (~16 bpm, switching estimator)
is roughly **2x** source1 (webcam) MAE (~10 bpm), and the correlation with
ground truth collapses from r=0.49 to r=0.17. This is not a small or
marginal gap.

**The isolating comparison — v1/source1 vs v1/source2, same subjects' pool,
same fixed-camera framing, same lighting, same distance — shows the gap is
almost entirely about the DEVICE, not the scenario.** MAE roughly doubles
(7.77 to 15.60 bpm) and r drops from 0.29 to 0.03 purely from switching
which camera captured the video, with every other condition held constant.
This is the cleanest evidence in this whole evaluation: the phone sensor,
compression, and optics are themselves the dominant source of the accuracy
loss, independent of how the phone is held.

**Hand-held motion (v8/v9) does NOT make things meaningfully worse than a
tripod-mounted phone (v1/source2).** v8+v9 pooled MAE (14.94-16.22
depending on estimator) is statistically indistinguishable from v1/source2's
MAE (15.60-16.35) — if anything, v8 (stable hand-held) has a slightly
*lower* chrom MAE (14.62) than v1/source2's fixed-mount phone (15.75). This
is a genuinely counter-intuitive finding worth stating plainly: **the
accuracy loss during defense will most likely come from "it's a phone
camera," not from "the presenter's hand is unsteady."** The 6.6x
higher dropped-frame rate documented in Section 2 is real and should still
be expected and shown as a known limitation, but it is not translating into
a proportionally larger HR error on top of the already-large phone-vs-webcam
gap.

**v7 (after-exercise) phone data (n=15) is the single worst-performing
group in this table (MAE 26-27 bpm)** — but n=15 is thin, and v7 already
carries its own known ground-truth noise (sensor fault codes, see
`VIPL_Scenario_Coverage.md` Section 2). This is not being treated as a
new finding about the phone specifically; it is consistent with v7 already
being the hardest scenario in the whole project for either device.

**The switching estimator does not close the phone gap.** On source2 data,
switching (POS-selection rate: 63/519 = 12.1% pool-wide) lands between raw
CHROM and raw POS as expected, but does not recover source1-level accuracy
— confirming this is a signal-quality/device problem the existing
CHROM/POS combiner logic cannot correct for post-hoc.

## 4. Recommendation for the defense demo

Given the ~2x MAE gap is a device effect and not primarily a motion effect,
the highest-value mitigation is anything that improves phone-specific signal
quality (exposure/ROI tuning, more stable framing, adequate lighting) rather
than asking the presenter to hold the phone extra still — the data here
suggests that alone would not close much of the gap. This should be stated
as an explicit, evidence-backed limitation in the defense presentation
rather than glossed over: the pipeline is validated and works, but its
phone-camera accuracy is measurably, not marginally, worse than its
webcam accuracy.

## 5. What was deliberately NOT done (Action 5 stop point)

Per the Task L brief, this pass stops here and does not extract v2-v7's
phone video (a substantially larger extraction, ~6 more scenarios x ~106
subjects each). Whether that is worth doing next depends on whether the
device-stratified gap found above is itself the main story worth deepening,
versus whether effort is better spent elsewhere — that judgment call is left
to whoever reads this report, not made unilaterally here.

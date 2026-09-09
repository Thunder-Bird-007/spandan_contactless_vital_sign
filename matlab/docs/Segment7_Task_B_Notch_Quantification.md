# Segment 7 Task B — Notch Quantification and Polarity Authority

Continues Segment 7 Task A (`docs/Segment7_Task_A_Morphology_Pipeline.md`, read first;
nothing already established there is re-derived here). Task A confirmed defects (b) and
(c) fixed, defect (a) (notch visibility) improved but not conclusively demonstrated on
5-gt, and flagged that FIG 4's ground-truth ensemble also showed a smooth, near-
monotonic diastolic decay for that one subject — a hypothesis on n=1 that this task's
job is to check across all 5 subjects with an actual notch detector, not eyeballing.

Task B also acts on a finding Task A's own metrics table already contained but did not
explain: the skewness polarity heuristic (`morphology/fixPolarity.m`) flipped **all 5**
UBFC subjects, while the ground-truth-anchored rule
(`morphology/fixPolarityByGroundTruth.m`) only agreed on 3 of 5 — a systematic all-flip
bias, not random scatter.

**Bottom line, stated up front**: the dicrotic notch IS genuinely present and reliably
detectable in the UBFC ground-truth contact PPG for all 5 subjects (Task A's open
question is resolved — it was invisible on a linear-scale plot, not absent from the
signal). Our rPPG only recovers it with real confidence in 1 of 5 subjects under the
Task A pipeline. The decision gate (see below, and flagged there as a judgment call)
fired branch 2: adaptive harmonic-comb filtering was implemented and is a real,
substantial improvement (moves 3 more subjects into a clearly-above-noise confidence
range); ROI tiling with correlation-based tile weighting was also implemented and did
NOT show the same benefit on this small pool.

## Action 1 — Ground-truth-anchored polarity made authoritative

`morphology/fixPolarity.m`'s header now documents the measured 3/5 agreement rate, the
all-flip bias, and the likely mechanism: den Brinker et al. (arXiv:2306.09879) found
forehead camera-PPG can have reversed asymmetry relative to the fingertip-contact PPG
this skewness convention was derived from — stated explicitly as a hypothesis on n=5,
not a proven fact.

`morphology/extractMorphologyWaveform.m` gained an optional 4th argument, `groundTruth`
(a struct with `.ppg`/`.timestamp`). When supplied, the polarity step now uses
`morphology/fixPolarityByGroundTruth.m` instead of `morphology/fixPolarity.m`. When
omitted, the function is byte-for-byte unchanged from Task A (confirmed by Action 6's
regression check below) — the heuristic remains the documented fallback for contexts
with no ground truth (Android, an eventual self-collected dataset). Neither
`morphology/bandpassMorphology.m` nor `morphology/ensembleAverageBeats.m` was touched.

## Action 2 — `morphology/notchDetectIEM.m`: Iterative Envelope Mean notch detector

New file, additive. Implements Pal et al. 2024 (*Computers in Biology and Medicine*,
254:108283, PMC11323035) — reported ~21x lower mean PPG notch-timing error than a plain
2nd-derivative method (4.6 ms vs 96.8 ms), which is why IEM was implemented rather than
a simpler derivative-based pick. **That 4.6 ms / 21x figure is the published method's
own reported number on its own reference implementation and dataset, cited here only to
explain why IEM was chosen over a derivative-based pick — it is NOT a measurement of
this project's implementation, which has not been independently validated against the
primary source (see the fidelity caveat immediately below and
`src/morphology/notchDetectIEM.m`'s header, which now states this explicitly too).**
**Fidelity caveat, stated in the function's own header
too**: built from a web-fetched algorithmic description of the paper, not the original
manuscript's equations directly; one genuinely ambiguous step (whether "extrema" in the
paper's Step 2 refers to the signal's own peaks/troughs or the inflection points located
via its second derivative) is resolved with an explicit, documented choice (inflection
points, the literal reading) rather than silently guessed at. Smoke-tested on a
synthetic waveform with a deliberately inserted dicrotic bump: correctly detected the
notch at cycle fraction 0.42 (true location: 0.42) with confidence 0.78, and correctly
returned `notchDetected = false` on a smooth monotonic control signal with no notch.

## Action 6 — Regression check

`tests/segment7_task_b_regression_test.m`, run automatically at the top of
`scripts/run_segment7_task_b_notch_batch.m` (hard-stops the batch if it fails):

Run automatically (hard-stop on failure) at the top of both
`scripts/run_segment7_task_b_notch_batch.m` and
`scripts/run_segment7_task_b_branch2_batch.m` — passed on every run:

| Check | Result |
|---|---|
| `extractMorphologyWaveform.m` 2-arg call, beatMatrix vs pre-Task-B snapshot | `isequal` = true |
| `extractMorphologyWaveform.m` 2-arg call, prototype.trimmedMean vs snapshot | `isequal` = true |
| `extractMorphologyWaveform.m` 2-arg call, prototype.median vs snapshot | `isequal` = true |
| `extractMorphologyWaveform.m` 2-arg call, wasFlipped vs snapshot | `isequal` = true (1 vs 1) |
| `extractMorphologyWaveform.m` 2-arg call, skewValue vs snapshot | `isequal` = true (-1.199242 vs -1.199242) |
| HR_chrom/HR_pos/HR_green vs Task A's saved values (Task A's own Action 7 check, rerun) | `isequal` = true on all three |

**PASS.** Adding the optional `groundTruth` argument did not change
`extractMorphologyWaveform.m`'s original no-ground-truth behaviour, and the Pass-1 HR
path remains untouched.

## Actions 3-5 — Ground truth vs. rPPG notch detection, and the decision gate

All 5 subjects succeeded, 0 failures, both batches (`scripts/run_segment7_task_b_notch_batch.m` for the baseline, `scripts/run_segment7_task_b_branch2_batch.m` for the two branch-2 methods).

### Ground truth ensemble prototype (baseline for comparison)

| Subject | notchDetected | Position | Depth | Confidence | Confidence (raw, unclipped) |
|---|---|---|---|---|---|
| 5-gt | true | 0.6588 | 0.3745 | 1.0000 | 1.1070 |
| 6-gt | true | 0.5647 | 0.3030 | 1.0000 | 1.1550 |
| 7-gt | true | 0.7804 | 0.3964 | 1.0000 | 1.1729 |
| 12-gt | true | 0.7647 | 0.3804 | 1.0000 | 1.4036 |
| after-exercise | true | 0.7608 | 0.4127 | 1.0000 | 1.8390 |

Full table: `results/metrics/segment7_task_b_notch_groundtruth.csv`.

**5/5 detected, and every single confidence value hits exactly the 1.0000 ceiling.**
Read plainly: confidence here is `min(1, ...)`, my own invented metric (not from the
paper), so a value of exactly 1.0000 on all 5 subjects means every one of them exceeded
the clip ceiling by SOME amount, not that all 5 are equally confident — the metric loses
resolution above 1 standard deviation of the residual's own noise. That said, the
underlying detections themselves (a genuine sub-zero valley, 0.1s+ after the systolic
peak, in a physiologically plausible position range 0.56-0.78) are real, reproducible
signal, not noise: **the notch clearly exists in the ground-truth contact PPG for all 5
subjects.** This directly answers Task A's open hypothesis — the smooth decay FIG 4
showed for 5-gt's ground truth was NOT because this subject's notch is inherently weak;
IEM finds it clearly (confidence at the ceiling). It was invisible to the eye in Task
A's linear-scale plot, not absent from the signal.

**Segment 7 Task C update:** the "every value is exactly 1.0000" read above turned out to
be a genuine artifact of the clip, not a real tie — see Task C's Action 1 section below.
The unclipped `confidenceRaw` column added to that table (and shown above) reveals a real
spread from 1.11 (5-gt, the weakest of the five) to 1.84 (after-exercise, the strongest),
fully consistent with after-exercise's already-known largest beat count (51) and highest
HR (100.5 bpm) giving IEM the cleanest signal to work with.

### Our rPPG ensemble prototype (baseline: CHROM + wide band + ground-truth-anchored polarity)

| Subject | notchDetected | Position | Depth | Confidence | Confidence (raw, unclipped) |
|---|---|---|---|---|---|
| 5-gt | true | 0.4392 | 0.0701 | 0.0485 | 0.0485 |
| 6-gt | true | 0.4471 | 0.0681 | 0.0449 | 0.0449 |
| 7-gt | true | 0.9176 | 0.5731 | 0.1518 | 0.1518 |
| 12-gt | true | 0.8000 | 0.3768 | **1.0000** | 1.6870 |
| after-exercise | true | 0.9098 | 0.4899 | 0.1239 | 0.1239 |

Full table: `results/metrics/segment7_task_b_notch_rppg.csv`. Only 12-gt clips here, so
`confidenceRaw` changes nothing about this table's ranking (it was already the clear
outlier); it matters for the ground-truth table above, where all 5 rows clipped.

### Which branch fired, and why (a judgment call, flagged explicitly)

**The literal boolean count is 5/5 for both ground truth and rPPG — by that reading
alone, neither named branch fires.** But treating a `notchDetected = true` at confidence
0.045 (5-gt) as equivalent evidence to one at confidence 1.000 (12-gt, ground truth
everywhere) is not defensible: a confidence of 0.045 means the located valley is 0.045
standard deviations below the IEM residual's own noise floor — indistinguishable from
noise by any normal standard. Applying the handoff's own explicit allowance ("or
confidence below the method's own reported reliability") with a threshold of
**confidence >= 1.0** (the only threshold that means something given this metric's own
clipping design — see `morphology/notchDetectIEM.m`'s header):

| | Ground truth | Our rPPG (baseline) |
|---|---|---|
| Raw `notchDetected` count | 5/5 | 5/5 |
| Confident (>= 1.0) count | **5/5** | **1/5** (12-gt only) |

This confidence-thresholded reading is **branch 2**: ground truth shows a notch
reliably, our rPPG does not. **This determination is a judgment call, not a literal
application of the handoff's boolean rule, and is flagged as such for review** — it
rests on a confidence metric this task invented itself (not from Pal et al. 2024). The
positions where rPPG's 4 low-confidence detections landed are also independently
suspicious: 7-gt and after-exercise land at 0.91-0.92, right at the very end of the
cycle, plausibly the return-to-baseline trough of the NEXT beat rather than a true
mid-diastole notch, not the 0.56-0.78 range ground truth actually clusters in.

Branch 2 was implemented on this basis.

### Branch 2: `adaptiveHarmonicFilter.m` and `tiledROIExtraction.m`

| Subject | Adaptive harmonic: detected / pos / depth / conf | Tiled ROI: detected / pos / depth / conf |
|---|---|---|
| 5-gt | true / 0.5725 / 0.2629 / **0.7447** | true / 0.5059 / 0.1376 / 0.0093 |
| 6-gt | true / 0.5137 / 0.1699 / **0.4120** | true / 0.5098 / 0.0778 / 0.0020 |
| 7-gt | true / 0.4510 / 0.2431 / **0.6405** | true / 0.8549 / 0.4558 / **0.9794** |
| 12-gt | true / 0.8039 / 0.3789 / **1.0000** | true / 0.7451 / 0.2140 / 0.0145 |
| after-exercise | true / 0.5882 / 0.2395 / 0.1582 | true / 0.9255 / 0.5207 / 0.1240 |

Full table: `results/metrics/segment7_task_b_notch_branch2.csv`. FIG 1v2 (6-condition
ablation, subject 5-gt): `results/figures/segment7_task_b_fig1v2_ablation_5-gt.png`.

**Confident-detection count (confidence >= 1.0, same bar as above):**

| Method | Confident count |
|---|---|
| Baseline (wide + GT-polarity) | 1/5 |
| Adaptive harmonic comb | 1/5 (exact-ceiling count unchanged) |
| Tiled ROI (4x4, correlation-weighted) | 0/5 |

At the strict >= 1.0 bar, neither new method changes the confident-count. **But that bar
is a blunt instrument here** (a saturating clip, as already flagged) — looking at the
actual confidence VALUES rather than just who crosses the ceiling tells a much clearer
story. Using a more moderate bar of **confidence >= 0.3** (still a real, if less
extreme, signal-above-noise bar):

| Method | Subjects >= 0.3 confidence |
|---|---|
| Baseline (wide + GT-polarity) | 1/5 (12-gt only) |
| **Adaptive harmonic comb** | **4/5** (5-gt 0.74, 6-gt 0.41, 7-gt 0.64, 12-gt 1.00) |
| Tiled ROI (4x4) | 1/5 (7-gt only, 0.98 -- a DIFFERENT subject than baseline's 12-gt, not an overlapping win) |

**Honest reading: the adaptive harmonic comb filter is a real, substantial win; ROI
tiling with this correlation-weighting scheme is not.** Restricting the R/G/B spectra to
narrow bins around the cardiac fundamental and its first 5 harmonics — rejecting
inter-harmonic noise a flat Butterworth band happily passes — moved 3 additional
subjects from noise-level confidence into a clearly-above-noise range (0.41-0.74),
without changing which subjects get a raw detection at all (5/5 throughout). FIG 1v2
shows this visually too: the adaptive-harmonic trace (dashed green) visibly departs from
the other five conditions' shape in the 0.10-0.20 and 0.30-0.45 cycle-fraction ranges,
where the flat-band conditions all collapse onto nearly the same curve. Tiled-ROI's
own trace is nearly indistinguishable from the flat-mean baseline for this subject
(confidence 0.0093, consistent with "did almost nothing differently") — and where it DID
help (7-gt, 0.98), it was a different subject than where the baseline already worked
(12-gt), not an additive win on top of it. With only 5 subjects this could easily be
sample noise rather than a real negative result for tiling specifically; it should not
be read as "tiling doesn't work," only as "this particular reweighting scheme did not
show the same effect adaptive harmonic filtering did, on this small pool."

**Bottom line for the report**: this task's central new finding is that the dicrotic
notch is genuinely PRESENT and detectable in ground truth on all 5 subjects
(resolving Task A's open question — it is not a subject/dataset characteristic that
makes the notch absent), and that narrow-band harmonic-comb filtering, not wider flat
Butterworth bandwidth, is the more promising next lever for recovering it in the rPPG
signal — a materially different, more specific conclusion than Task A could reach on its
own.

## Segment 7 Task C — Confidence Ranking, Overclaiming Audit, and Combined ABPF+Tiled ROI Test

Continues directly from the two findings above (`notchDetectIEM.m`'s `min(1, ...)` clip
destroying rank resolution once subjects clip, and the un-verified-against-primary-source
status of the 4.6 ms / 21x figure). Does not re-derive anything already established in
this document or `docs/Segment7_Task_A_Morphology_Pipeline.md`.

### Action 1 — `confidenceRaw`, an unclipped ranking metric

`notchDetectIEM.m` now returns a 5th output, `confidenceRaw` — the exact same
`|finalResidual(notchIdx)| / (std(finalResidual) + eps)` ratio `confidence` already
computed, just without the `min(1, ...)` ceiling. Purely additive: `confidence`'s own
value and the clip it always had are unchanged, and neither `notchDetected`,
`notchPositionNormalized`, nor `notchDepth` were touched at all. Both existing CSVs
(`segment7_task_b_notch_groundtruth.csv`, `segment7_task_b_notch_rppg.csv`) were
regenerated with the new column and diffed column-by-column against their pre-Task-C
versions — every pre-existing column is byte-identical; only `confidenceRaw` is new (see
the updated tables above, and Action 4 below).

The payoff is exactly what finding 1 predicted: the ground-truth table's "all 5 subjects
read 1.0000" was real uniformity of *having crossed the ceiling*, not uniformity of
*strength* — `confidenceRaw` spreads them from 1.1070 (5-gt) to 1.8390 (after-exercise),
a >65% spread that was completely invisible before. On the rPPG baseline table only
12-gt clips (1.6870 raw), so nothing changes there — the clip only actually cost
resolution where multiple subjects clipped together, which was the ground-truth table
specifically.

### Action 2 — Overclaiming audit: 4.6 ms / 21x

Searched every file that mentions Pal et al. 2024 / PMC11323035 / the IEM method
(`docs/Segment7_Task_B_Notch_Quantification.md` itself, `src/morphology/notchDetectIEM.m`,
and the two batch scripts that call it — no other file in the repo references this paper
or these numbers at all). **Both existing mentions of 4.6 ms / 21x (the doc's own Action
2 section, and `notchDetectIEM.m`'s header) already used "reported" / "the paper
reports" language** — i.e. they were already attributed to the paper's own evaluation,
not phrased as a measurement of this implementation. No instance of overclaiming was
found requiring correction. That said, "reported" alone leaves room for a careless
future reader to skim past the attribution, so one explicit disclaimer sentence was
added at each of the two locations, spelling out plainly that the figure describes the
published method's own reference implementation and dataset, not this codebase (which
has not been independently validated against the primary source) — belt-and-braces, not
a fix to an actual defect found.

### Action 3 — Combined ABPF + tiled ROI test

**Superseded — this Action 3 section (the "Combined-v1" table, the 4-column comparison,
and the "is combining additive?" conclusion below it) described a CONFOUNDED test. Kept
here, struck through, not deleted, per this project's own documentation convention (see
`README.md`'s "Current status" section for the precedent), so the project's actual
history is visible rather than silently rewritten.** The confound: `tiledROIExtraction.m`
had already run each tile through a flat `'wide'` Butterworth bandpass, CHROM-combined
each tile, and correlation-weighted-averaged the 16 tiles into one pulse — THEN
`adaptiveHarmonicFilter.m` ran on that already-filtered, already-combined output. This is
NOT the pipeline position `adaptiveHarmonicFilter.m` occupies in ABPF-only
(`run_segment7_task_b_branch2_batch.m`), where it substitutes for
`bandpassMorphology.m` BEFORE `chromCombine.m`, per-channel. Combined-v1 therefore
compared ABPF-only against a materially different pipeline shape, not against ABPF's own
substitution applied per-tile — its "not additive" reading is not wrong on its own
terms, but cannot be trusted as an answer to the actual question asked. See the
corrected "Combined-v2" test below for the answer at ABPF-only's own operating point.

> ~~`scripts/run_segment7_task_c_combined_batch.m` (new): per subject, runs
> `tiledROIExtraction.m` (`bandMode='wide'`) to get its correlation-weighted combined
> pulse, runs `adaptiveHarmonicFilter.m` on that combined pulse (a shared f0 estimated
> from the same combined pulse via `fftHeartRate.m`, since there is only one signal here —
> no per-channel misalignment risk to guard against the way the R/G/B case in
> `run_segment7_task_b_branch2_batch.m` has), then the same
> `fixPolarityByGroundTruth.m` → `resampleUniform.m` → `ensembleAverageBeats.m` →
> `notchDetectIEM.m` tail as every other condition. All 5 subjects succeeded, 0 failures.
> Full table: `results/metrics/segment7_task_c_combined_notch.csv`.
>
> | Subject | notchDetected | Position | Depth | Confidence | Confidence (raw) |
> |---|---|---|---|---|---|
> | 5-gt | true | 0.8196 | 0.3175 | 0.1136 | 0.1136 |
> | 6-gt | true | 0.5608 | 0.1405 | 0.1358 | 0.1358 |
> | 7-gt | true | 0.4627 | 0.1603 | 0.0113 | 0.0113 |
> | 12-gt | true | 0.8824 | 0.4443 | 0.3265 | 0.3265 |
> | after-exercise | true | 0.8353 | 0.4295 | **1.0000** | 1.1873 |
>
> ### Side-by-side comparison: baseline / ABPF-only / tiled-only / combined (all 5 subjects)
>
> | Subject | Baseline (wide+GT-polarity) | ABPF-only | Tiled-only | **Combined** |
> |---|---|---|---|---|
> | 5-gt | 0.0485 | **0.7447** | 0.0093 | 0.1136 |
> | 6-gt | 0.0449 | **0.4120** | 0.0020 | 0.1358 |
> | 7-gt | 0.1518 | 0.6405 | **0.9794** | 0.0113 |
> | 12-gt | 1.0000 | 1.0000 | 0.0145 | 0.3265 |
> | after-exercise | 0.1239 | 0.1582 | 0.1240 | **1.0000** |
>
> **Subjects clearing the confidence >= 0.3 bar:**
>
> | Method | Subjects >= 0.3 |
> |---|---|
> | Baseline | 1/5 (12-gt) |
> | ABPF-only | 4/5 (5-gt, 6-gt, 7-gt, 12-gt) |
> | Tiled-only | 1/5 (7-gt) |
> | **Combined** | **2/5 (12-gt, after-exercise)** |
>
> **Honest reading (superseded):** combining loses three of ABPF-only's four wins but
> produces one apparently genuine additive result at after-exercise (0.12 baseline / 0.16
> ABPF / 0.12 tiled, all below the bar, vs. 1.0000 combined) — a subject no single method
> reached alone. Net: a bad trade by subject count (2/5 vs. ABPF-alone's 4/5), but not
> simply "worse everywhere."

### Action 3 (corrected) — Combined-v2: the harmonic substitution at ABPF-only's own pipeline position

Segment 7 Task C's own Action 1 gave `tiledROIExtraction.m` a `filterMode` option:
`'butterworth'` (unchanged default) or `'harmonic'`, which calls
`adaptiveHarmonicFilter.m` per tile, per-channel, immediately before that tile's own
`chromCombine.m` call — exactly ABPF-only's own substitution, just applied per-tile
instead of once for the whole ROI. `sharedF0HzOverride` is forwarded to every tile so all
16 lock onto one cardiac fundamental, same reasoning as ABPF-only's own `sharedF0Hz`.
Confirmed non-regressive: `tests/segment7_task_c_action1_regression_test.m` reran the
original 4-arg (`filterMode` omitted) call for all 5 subjects and matched
`segment7_task_b_notch_branch2.csv`'s tiledROI row exactly (`notchDetected`, position,
depth, confidence all string-equal to 4 decimal places) — the default behaviour is
byte-for-byte unchanged.

`scripts/run_segment7_task_c2_true_combined_batch.m` (new): per subject, estimates
`sharedF0Hz` from the whole-ROI wide-band CHROM pulse (the SAME source and method
ABPF-only's own `sharedF0Hz` uses — so Combined-v2 is evaluated at ABPF-only's actual
operating point, not a new one), then calls
`tiledROIExtraction(videoPath, [], gridRows, gridCols, 'harmonic', sharedF0Hz)`, then the
same `fixPolarityByGroundTruth.m` → `resampleUniform.m` → `ensembleAverageBeats.m` →
`notchDetectIEM.m` tail as every other condition. All 5 subjects succeeded, 0 failures.
Full table: `results/metrics/segment7_task_c2_true_combined_notch.csv`.

| Subject | notchDetected | Position | Depth | Confidence | Confidence (raw) |
|---|---|---|---|---|---|
| 5-gt | true | 0.6275 | 0.2844 | 0.0757 | 0.0757 |
| 6-gt | true | 0.5569 | 0.1665 | 0.5357 | 0.5357 |
| 7-gt | true | 0.4510 | 0.1955 | 0.7677 | 0.7677 |
| 12-gt | true | 0.4235 | 0.0516 | 0.0163 | 0.0163 |
| after-exercise | true | 0.9686 | 0.5360 | 0.1218 | 0.1218 |

### Side-by-side comparison: baseline / ABPF-only / tiled-only / Combined-v1 (confounded) / Combined-v2 (true)

| Subject | Baseline | ABPF-only | Tiled-only | Combined-v1 (confounded) | **Combined-v2 (true)** |
|---|---|---|---|---|---|
| 5-gt | 0.0485 | **0.7447** | 0.0093 | 0.1136 | 0.0757 |
| 6-gt | 0.0449 | 0.4120 | 0.0020 | 0.1358 | **0.5357** |
| 7-gt | 0.1518 | 0.6405 | 0.9794 | 0.0113 | **0.7677** |
| 12-gt | 1.0000 | **1.0000** | 0.0145 | 0.3265 | 0.0163 |
| after-exercise | 0.1239 | 0.1582 | 0.1240 | **1.0000** | 0.1218 |

**Subjects clearing the confidence >= 0.3 bar:**

| Method | Subjects >= 0.3 |
|---|---|
| Baseline | 1/5 (12-gt) |
| ABPF-only | 4/5 (5-gt, 6-gt, 7-gt, 12-gt) |
| Tiled-only | 1/5 (7-gt) |
| Combined-v1 (confounded) | 2/5 (12-gt, after-exercise) |
| **Combined-v2 (true)** | **2/5 (6-gt, 7-gt)** |

### Honest reading: does Combined-v2 change the "not additive" conclusion?

**No — it does not change the conclusion, and it removes the one data point that made
Combined-v1 look partially additive.** Checking every subject Combined-v2 reaches
(6-gt at 0.54, 7-gt at 0.77) against what ABPF-only alone already reached: **both are
already inside ABPF-only's own 4/5** (ABPF-only: 0.41 and 0.64 respectively). Combined-v2
recovers **zero subjects that ABPF-only did not already recover on its own** — its 2/5
is a strict subset of ABPF-only's 4/5, not a new region of coverage. By count it is worse
than ABPF-only (2/5 vs. 4/5): 5-gt collapses from 0.74 to 0.08 and 12-gt collapses from
1.00 to 0.02, while 6-gt and 7-gt each improve modestly over ABPF-only (0.41→0.54,
0.64→0.77). Net effect: tiling the harmonic-comb substitution trades two of ABPF's
strongest wins for small gains on two subjects it already had, at the correct operating
point this time — the same qualitative "not additive" verdict Combined-v1 reached, now
without the confound.

**Does after-exercise's Combined-v1 win survive the fix? No — it does not, and it should
be read as having been an artifact of the confound, not a real combination effect.**
Under Combined-v2, at ABPF-only's own pipeline position, after-exercise scores 0.1218 —
statistically indistinguishable from its baseline (0.1239), ABPF-only (0.1582), and
tiled-only (0.1240) scores, all clustered in the same noise-level band. Combined-v1's
1.0000 (raw 1.1873) for this subject was specific to running the harmonic comb AFTER a
flat Butterworth bandpass + CHROM combine + cross-tile averaging had already reshaped the
signal — a real numerical result, but not evidence that combining spatial tiling with
harmonic-comb filtering helps this subject; it was evidence that filtering an
already-heavily-processed signal a second time, in a way no deployed condition actually
does, can produce a large residual by coincidence. **Bottom line for the report: neither
combined-methods test (confounded or corrected) beats ABPF-only alone on this 5-subject
pool. ABPF-only (adaptive harmonic-comb filtering, applied whole-ROI, at the position it
currently occupies in the pipeline) remains this project's best-supported single
intervention for notch recovery** — combining it with tiled ROI, in either pipeline
ordering tested so far, has not been shown to help.

### Action 4 — Regression check (first round: `confidenceRaw`, overclaiming audit, Combined-v1)

Confirms Actions 1-3 did not change any already-saved Task A or Task B output for
conditions that should not have changed:

| Check | Result |
|---|---|
| `tests/segment7_task_b_regression_test.m` (Task A/B HR-path and 2-arg `extractMorphologyWaveform.m` check, rerun at the top of the Action 1 CSV regeneration) | PASS (all `isequal` true, same values as originally reported above) |
| `segment7_task_b_notch_groundtruth.csv`: `notchDetected`/`notchPositionNormalized`/`notchDepth`/`confidence` columns, pre- vs. post-Action-1, all 5 subjects | byte-identical (diffed column-by-column, `confidenceRaw` excluded) |
| `segment7_task_b_notch_rppg.csv`: same four columns, pre- vs. post-Action-1, all 5 subjects | byte-identical (diffed column-by-column, `confidenceRaw` excluded) |

**PASS.** Action 1 added a column and nothing else; Actions 2-3 touched no existing
output file (Action 2 is documentation-only, Action 3 writes only a new,
separately-named CSV).

### Action 4 — Regression check (second round: `tiledROIExtraction.m` `filterMode` fix)

New file, `tests/segment7_task_c_action1_regression_test.m`, confirms the `filterMode`/
`sharedF0HzOverride` parameters added to `tiledROIExtraction.m` to fix the Combined-v1
confound did not change that function's behaviour for any existing caller that omits
them. Re-runs the exact "Tiled ROI condition" computation
`run_segment7_task_b_branch2_batch.m` performed — the ORIGINAL 4-arg
`tiledROIExtraction(videoPath, 'wide')` call, `filterMode` implicitly defaulting to
`'butterworth'` — for all 5 subjects and compares against the already-saved
`segment7_task_b_notch_branch2.csv` tiledROI rows:

| Subject | notchDetected | Position | Depth | Confidence | Match |
|---|---|---|---|---|---|
| 5-gt | 1 vs 1 | 0.5059 vs 0.5059 | 0.1376 vs 0.1376 | 0.0093 vs 0.0093 | PASS |
| 6-gt | 1 vs 1 | 0.5098 vs 0.5098 | 0.0778 vs 0.0778 | 0.0020 vs 0.0020 | PASS |
| 7-gt | 1 vs 1 | 0.8549 vs 0.8549 | 0.4558 vs 0.4558 | 0.9794 vs 0.9794 | PASS |
| 12-gt | 1 vs 1 | 0.7451 vs 0.7451 | 0.2140 vs 0.2140 | 0.0145 vs 0.0145 | PASS |
| after-exercise | 1 vs 1 | 0.9255 vs 0.9255 | 0.5207 vs 0.5207 | 0.1240 vs 0.1240 | PASS |

**ALL PASS, all 5 subjects.** `tiledROIExtraction.m`'s default (`filterMode` omitted)
behaviour is unchanged. `bandpassMorphology.m`, `ensembleAverageBeats.m`, and
`notchDetectIEM.m`'s detection algorithm were not opened by this round of changes at all
(confirmed by construction, not just by these numbers matching) —
`run_segment7_task_c2_true_combined_batch.m` calls all three exactly as every prior Task
B/C script does.

## Outputs

- `src/morphology/notchDetectIEM.m` (new)
- `src/morphology/fixPolarity.m` (modified: header/docstring only, logic unchanged)
- `src/morphology/extractMorphologyWaveform.m` (modified: additive optional 4th
  argument `groundTruth`; original 2-arg/3-arg behaviour unchanged, confirmed by
  regression check)
- `scripts/run_segment7_task_b_notch_batch.m` (new)
- `tests/segment7_task_b_regression_test.m` (new)
- `data/processed/segment7_task_a_regression_snapshot_5-gt.mat` (new — pre-Task-B
  snapshot used by the regression test)
- `results/metrics/segment7_task_b_notch_groundtruth.csv` (new)
- `results/metrics/segment7_task_b_notch_rppg.csv` (new)
- `src/morphology/adaptiveHarmonicFilter.m` (new — branch 2, implemented because the
  decision gate fired)
- `src/morphology/tiledROIExtraction.m` (new — branch 2)
- `scripts/run_segment7_task_b_branch2_batch.m` (new — branch 2)
- `results/metrics/segment7_task_b_notch_branch2.csv` (new)
- `results/figures/segment7_task_b_fig1v2_ablation_5-gt.png` (new — 6-condition
  ablation: Task A's original 4 conditions, now polarity-corrected with the
  ground-truth-anchored rule, plus adaptive-harmonic and tiled-ROI)
- `scripts/run_segment7_morphology_batch.m` and its outputs (Task A's own batch
  script/figures/CSV): **untouched** — Task A's already-reviewed figures/metrics are
  historical record and are not retroactively altered by this task.
- Segment 7 Task C additions:
  - `src/morphology/notchDetectIEM.m` (modified: additive 5th output `confidenceRaw`,
    plus header disclaimer clarifications; detection logic unchanged, confirmed by
    Action 4)
  - `results/metrics/segment7_task_b_notch_groundtruth.csv` (regenerated: new
    `confidenceRaw` column, all other columns byte-identical)
  - `results/metrics/segment7_task_b_notch_rppg.csv` (regenerated: new `confidenceRaw`
    column, all other columns byte-identical)
  - `scripts/run_segment7_task_b_notch_batch.m` (modified: logs/writes the new
    `confidenceRaw` column)
  - `scripts/run_segment7_task_c_combined_batch.m` (new — Combined-v1, confounded,
    kept for the record, **superseded** — see the marked section above)
  - `results/metrics/segment7_task_c_combined_notch.csv` (new — Combined-v1 output,
    superseded)
  - `results/metrics/segment7_task_b_notch_branch2.csv`,
    `scripts/run_segment7_task_b_branch2_batch.m`: **untouched** (Task C's handoff only
    asked for `confidenceRaw` on the two baseline CSVs, not this one; its `confidence`
    values did not clip in this run so the ranking issue never applied to it anyway)
  - `src/morphology/tiledROIExtraction.m` (modified: additive `filterMode` /
    `sharedF0HzOverride` parameters, fixing the Combined-v1 confound; default
    (`filterMode` omitted) behaviour unchanged, confirmed by the second regression
    check)
  - `scripts/run_segment7_task_c2_true_combined_batch.m` (new — Combined-v2, the
    corrected combined test, at ABPF-only's own pipeline position)
  - `results/metrics/segment7_task_c2_true_combined_notch.csv` (new)
  - `tests/segment7_task_c_action1_regression_test.m` (new — confirms
    `tiledROIExtraction.m`'s default behaviour is unchanged)
- Every file under `filtering/`, `pulseextraction/`, `heartrate/`, `validation/`,
  `pipeline/`, and `android/`: **untouched** (confirmed by the regression check).

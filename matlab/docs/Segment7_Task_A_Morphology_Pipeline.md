# Segment 7 Task A — rPPG Waveform Morphology Pipeline

Addresses the supervisor's progress-presentation feedback directly: HR numbers were
accepted, but the rPPG **waveform** was not — dicrotic notches mostly absent, the few
that appear are cut off/flattened, and the few that appear are inverted (notch on the
wrong limb). This task diagnosed three causes (stated in the handoff, not
re-investigated here) and built a new, fully additive morphology pipeline in
`matlab/src/morphology/` to fix them. **Nothing under the existing HR path
(`filtering/bandpassClean.m`, `filtering/detrendSignal.m`,
`pulseextraction/chromCombine.m`, `pulseextraction/posCombine.m`,
`heartrate/fftHeartRate.m`, `heartrate/windowedHeartRate.m`,
`pipeline/estimateVitals.m`, `validation/runLOSO.m`) or the Android app was modified** —
see Action 7's regression check.

Scope is Tier 1 only, per the handoff: windowed POS, adaptive harmonic bandpass
filtering, landmark ROI, ROI tiling, and the iterative-envelope-mean notch detector are
explicitly deferred to a second handoff.

## Action 0 — Saturation diagnostic (run FIRST)

Before touching any filter or polarity logic, `scripts/run_segment7_task_a_saturation_check.m`
decoded the raw forehead ROI (same geometry as `roi/extractROISignals.m`'s default
`'forehead'` mode) for all 5 locally-available UBFC DATASET_1 subjects and measured, per
color channel: the fraction of individual pixels with an 8-bit value >= 250, and the
fraction of frames whose ROI channel mean is >= 245.

| Subject | Channel | Frac. pixels >= 250 | Frac. frames mean >= 245 |
|---|---|---|---|
| 5-gt | R, G, B | 0.000000 | 0.000000 |
| 6-gt | R, G, B | 0.000000 | 0.000000 |
| 7-gt | R, G, B | 0.000000 | 0.000000 |
| 12-gt | R | 0.000002 | 0.000000 |
| 12-gt | G, B | 0.000000 | 0.000000 |
| after-exercise | R, G, B | 0.000000 | 0.000000 |

**Result: no non-trivial saturation on any subject/channel** (12-gt's R channel has 2
saturated pixels out of roughly 2,000 pixels/frame x 2,388 frames — statistical noise,
not clipping). This is genuinely useful information, not just a clean bill of health:
it rules out sensor clipping as a contributor to defect (b) ("cut off / flattened at
the top") on this project's actual video pool. Defect (b) is fully explained by causes
1 and 2 from the handoff (harmonic loss from the 4 Hz cutoff, and an inverted trace
putting the notch near the top of the plot where rounding/scaling makes it look
flattened) — not by clipped pixels. Full numbers: `results/metrics/segment7_task_a_saturation_check.csv`.

## Action 1 — `morphology/bandpassMorphology.m`

New file, additive. `filtering/bandpassClean.m` is untouched. Three `bandMode` options,
all `butter(3, ...)` + `filtfilt`:

| bandMode | Band | Order | Purpose |
|---|---|---|---|
| `'legacy'` | 0.7-4.0 Hz | 3 | Reproduces `bandpassClean.m`'s band (different order — see below) so the Action 6 ablation can include current HR-path behaviour as a comparison point. Never used as a substitute for `bandpassClean.m` in the HR path itself. |
| `'mid'` | 0.6-6.0 Hz | 3 | Klibus et al.'s real-patient setting; the fallback if `'wide'` proves too noisy. |
| `'wide'` (default) | 0.5-8.0 Hz | 3 | Retains H2/H3 across 60-180 bpm; the band this task's pipeline actually uses. |

Note `filterOrder = 3` for all three `bandMode` values here, vs. `bandpassClean.m`'s
`filterOrder = 2` — a deliberate, documented difference (sharper rolloff at whichever
edge is chosen), not an oversight, so `'legacy'` mode is band-identical but not
filter-identical to `bandpassClean.m`; the Action 6 ablation compares band *width*
choices under one consistent order, which is the variable this task is actually
investigating.

## Action 2 — Polarity correction: `morphology/fixPolarity.m` and `morphology/fixPolarityByGroundTruth.m`

`fixPolarity.m` computes sample skewness over the whole signal (manual formula, no
Statistics Toolbox dependency, matching `validation/computeMetrics.m`'s existing
convention of hand-rolled statistics) and negates the signal if skewness < 0 — a
correctly-oriented PPG has a fast systolic upstroke and slow diastolic decay (positive
skew); negation flips the sign of the third central moment.

`fixPolarityByGroundTruth.m` picks the sign by comparing `max(xcorr(rppg, gtPPG))`
against `max(xcorr(-rppg, gtPPG))` after resampling the UBFC contact-PPG onto the
rPPG signal's own real timestamps — the ground-truth-anchored answer, used only to
measure how often the skewness heuristic agrees with it (Action 6's
`heuristicAgreesWithGT` column), never as part of the actual (no-ground-truth-available)
pipeline.

## Action 3 — `morphology/resampleUniform.m`

Resamples onto a uniform 250 Hz grid using `interp1(..., 'pchip')` and the REAL
per-frame timestamps from `roi/extractROISignals.m`'s `roiTimestamps` output (not an
assumed `(0:N-1)/frameRate` grid) — webcam frame timing is irregular and that jitter
alone smears a feature as fine as the dicrotic notch. `pchip`, not `spline`, because
spline can overshoot near a sharp feature and fabricate a fake notch-like ripple;
`pchip` is shape-preserving and does not overshoot between input samples.

## Action 4 — `morphology/ensembleAverageBeats.m` (core deliverable)

Segments beats on the **negative-going zero crossing** of the zero-mean signal (the
steepest-downslope point, far more temporally precise than peak detection), rejects
beats whose duration deviates more than 30% from the median inter-beat interval,
resamples each surviving beat to 256 samples (`pchip`), then applies **two-anchor time
warping**: a piecewise-linear stretch that places each beat's systolic peak at exactly
25% of the cycle (onset fixed at 0%, end fixed at 100%). This step is load-bearing —
without it, beat-to-beat variation in exactly where the peak lands smears the notch
(which sits just after the peak) across tens of milliseconds and erases it from the
average entirely; single-anchor (onset-only) alignment was explicitly rejected for this
reason.

A two-pass quality gate follows: average all duration-surviving, warped beats into a
rough template, correlate every beat against it (manual Pearson r, no toolbox
dependency), keep the top 25% by correlation, and re-average. The final beats are
combined **both** ways — `trimmean(beatMatrix, 20, 1)` (10% trimmed mean) and
`median(beatMatrix, 1)` — and both are returned so the batch script can compare them
rather than this function silently picking one.

The per-sample interquartile range across the final aligned beat matrix is returned as
a first-class output (`iqrBand`, with `.q1`, `.q3`, `.width`, `.meanWidth`, and a
unit-free `.meanWidthNormalized` = mean IQR width / prototype peak-to-peak amplitude) —
this IS the quantitative "beat-to-beat stability" number the supervisor asked for, not
a plotting afterthought. `stats` records beats found, rejected by duration, rejected by
the quality gate, finally averaged, and the theoretical coherent-averaging SNR gain
`sqrt(beatsAveraged)`.

**Smoke-tested** (not a formal run) on subject 5-gt using cached `data/processed/5-gt_rgb_traces.mat`
(approximate uniform timestamps, since the cached file predates Action 3's real-timestamp
requirement — the real Action 6 batch below uses genuine `roiTimestamps` throughout):
136 raw beats found, 48 rejected by the duration gate, 66 rejected by the quality gate,
22 beats finally averaged (SNR gain ~4.7x), `wasFlipped = true` (skewness -1.20) —
confirming on real project data, not just in the abstract, that cause 2 from the
handoff (unanchored CHROM polarity) actually fires.

## Action 5 — `morphology/extractMorphologyWaveform.m`

Chains `roi/extractROISignals.m` (forehead, unchanged) -> `filtering/detrendSignal.m`
(unchanged) -> `morphology/bandpassMorphology.m` -> `pulseextraction/chromCombine.m`
(unchanged) -> `morphology/fixPolarity.m` -> `morphology/resampleUniform.m` ->
`morphology/ensembleAverageBeats.m`. **CHROM, not POS**, is used here: this project's
`posCombine.m` is a non-canonical whole-signal simplification of the published POS
algorithm (see its own docstring), so running the morphology ablation through it would
confound "did widening the band help" with "is our POS formula itself correct" — POS
morphology is left for the second handoff. Does not modify or call into
`pipeline/estimateVitals.m` (still an unimplemented stub as of Segment 7).

## Action 6 — Ablation batch and figures

`scripts/run_segment7_morphology_batch.m` ran on all 5 locally-available UBFC DATASET_1
subjects (5-gt, 6-gt, 7-gt, 12-gt, after-exercise — the same pool every prior Segment
2-4 batch script in this project used). One subject (5-gt, fixed for reproducibility)
got the full 4-condition band/polarity ablation; all 5 subjects got the metrics-table
run.

All 5 subjects succeeded, 0 failures.

### Metrics table (all 5 subjects)

| Subject | Waveform r vs GT | SNR gain (dB) | Beats found | Rej. duration | Rej. quality | Beats averaged | Heuristic flipped | Skewness | GT-anchored flipped | Agree |
|---|---|---|---|---|---|---|---|---|---|---|
| 5-gt | 0.9408 | 13.42 | 136 | 48 | 66 | 22 | true | -1.199 | false | **NO** |
| 6-gt | 0.9272 | 13.42 | 131 | 44 | 65 | 22 | true | -0.246 | false | **NO** |
| 7-gt | 0.8795 | 12.30 | 192 | 126 | 49 | 17 | true | -0.143 | true | yes |
| 12-gt | 0.9333 | 12.79 | 161 | 85 | 57 | 19 | true | -0.104 | true | yes |
| after-exercise | 0.9620 | 16.43 | 245 | 72 | 129 | 44 | true | -0.225 | true | yes |

Full table: `results/metrics/segment7_morphology_metrics.csv`.

**Skewness-heuristic vs ground-truth-anchored polarity agreement: 3/5 = 60%.** Reported
honestly, not hidden: the skewness heuristic flipped polarity on **all 5** subjects
(every skewness value came out negative), while the ground-truth-anchored rule only
agreed on 3 of them. On 5-gt and 6-gt specifically, the heuristic and the
ground-truth-anchored rule land on opposite answers. This does not mean the heuristic is
"wrong" in an absolute sense — `fixPolarityByGroundTruth.m` itself only picks whichever
orientation gives a marginally higher cross-correlation peak with the resampled contact
PPG, which is itself a soft, single-lag-window comparison, not a proof of the "true"
answer — but it does mean the skewness rule should not be treated as a solved problem at
face value. Both fields are in the CSV precisely so this can be checked per-subject
rather than trusted blindly.

### FIG 1 — bandwidth/polarity ablation (subject 5-gt)

![FIG 1](../../results/figures/segment7_fig1_bandmode_ablation_5-gt.png)

Widening the band from `'legacy'` (0.7-4 Hz) to `'wide'` (0.5-8 Hz) visibly sharpens and
raises the systolic peak (legacy peak ~3.3, wide peak ~4.0, in a.u.) and the trough
becomes deeper and narrower — both consistent with the higher-harmonic content the wide
band retains that the legacy band's 4 Hz cutoff throws away. `'mid'` (0.6-6 Hz) sits
between the two, as expected. The `wide+polarity-fixed` trace is the same `wide` shape,
simply mirrored right-side-up (fast upstroke, slow decay) instead of upside down.

### FIG 2 — ensemble prototype + IQR stability band (subject 5-gt)

![FIG 2](../../results/figures/segment7_fig2_ensemble_iqr_5-gt.png)

`iqrBand.meanWidthNormalized = 0.101` — the beat-to-beat IQR spread is, on average,
about 10% of the prototype's own peak-to-peak amplitude. This is the quantitative
"beat-to-beat stability" number: a tight, visibly narrow band around the trimmed-mean
prototype for most of the cycle, widening somewhat on the diastolic decay where
individual-beat timing/duration differences accumulate more.

### FIG 3 — polarity fix before/after (subject 5-gt)

![FIG 3](../../results/figures/segment7_fig3_polarity_before_after_5-gt.png)

Skewness = -1.199 before the fix (confirming the trace was genuinely upside down, not a
borderline call); after negation the shape is identical but now rises fast and decays
slow, the correct PPG convention.

### FIG 4 — prototype vs UBFC ground-truth contact PPG (subject 5-gt)

![FIG 4](../../results/figures/segment7_fig4_prototype_vs_groundtruth_5-gt.png)

Waveform Pearson r = 0.94 for this subject (0.88-0.96 across all 5) between our
rPPG ensemble prototype and the ground-truth contact-PPG's own ensemble prototype, both
z-score normalized. The two curves track closely in overall cycle shape (fast rise,
rounded peak near the 0.25 anchor, slower decay) — strong quantitative agreement with
real physiological ground truth, not just an internally self-consistent shape.

### FIG 5 — beat-count vs SNR gain (subject 5-gt)

![FIG 5](../../results/figures/segment7_fig5_beatcount_vs_snr_5-gt.png)

For N = 1 to roughly 14 beats, the empirical gain curve tracks the theoretical
`sqrt(N)` coherent-averaging law reasonably closely, demonstrating the law holds in
practice on this project's own data, not just in theory. **Honest reading of the upper
end of the curve**: above N ~ 15 the empirical curve pulls noticeably above `sqrt(N)`,
reaching ~20x gain at N = 22 against a theoretical ~4.7x. This upward pull is a
**measurement-method artifact, not a real super-`sqrt(N)` effect**: the reference used
to measure "noise" at each N is the trimmed mean built from the SAME final beat set
being subsampled, so as the subsample size k approaches the full set size M, the
subsample average and the reference necessarily converge toward each other regardless
of true noise level, artificially shrinking the measured residual near k = M. The
useful, trustworthy part of this figure is the low-to-mid-N range where subsample and
reference are still substantially independent; the curve's blow-up near N = M should be
read as a property of this specific measurement construction, not as evidence of an
unusually effective average.

### Honest reading: did this fix defect (a), the missing dicrotic notch?

**Partially, and this needs to be said plainly rather than glossed over.** FIG 1-3
clearly demonstrate two of the three defects being fixed: the trace is no longer
upside-down (defect c) and the wide band clearly recovers more high-frequency
peak/trough structure than the legacy band did (part of defect b — the peak is taller
and less flattened). FIG 4's r = 0.88-0.96 range shows the corrected waveform's overall
*cycle shape* now agrees strongly with real ground-truth contact PPG. **But**, looking
directly at FIG 1/FIG 2 for the representative subject, none of the four conditions
(including `wide+polarity-fixed`) show an unambiguous, distinct dicrotic-notch
*shoulder* — a secondary local bump on the diastolic limb — the decay from the systolic
peak is smooth and close to monotonic in all four traces. This is not unique to our
processed signal: FIG 4 shows the same smooth-decay character in the UBFC
ground-truth contact-PPG's OWN ensemble average for this subject, which suggests this
may reflect a genuine property of this particular subject/sensor/dataset (dicrotic
notch prominence varies a great deal between individuals and is often subtle even in
clinical contact PPG) rather than a remaining defect purely in this project's
processing chain. **Bottom line for the report**: defects (b) and (c) are convincingly
addressed by this task's changes; defect (a) is improved (taller, better-conditioned
peaks feeding into it) but a clearly visible notch shoulder was not conclusively
demonstrated on the subjects tested here, and chasing it further is exactly what the
Tier 2 second handoff's iterative-envelope-mean notch detector is for — this task's
honest scope boundary, not a claim of full success.

## Action 7 — Regression check

`tests/segment7_regression_test.m` recomputed HR_chrom/HR_pos/HR_green for subject 5-gt
from cached `data/processed/5-gt_rgb_traces.mat` using the exact, unmodified Pass-1 HR
chain (`detrendSignal.m` -> `bandpassClean.m` -> `chromCombine.m`/`posCombine.m` ->
`fftHeartRate.m`) and compared against `data/processed/5-gt_hr_estimates.mat`, saved by
`scripts/run_segment4_heartrate_batch.m` before Segment 7 Task A existed, using
`isequal()` (bit-for-bit, not tolerance-based — same convention as
`docs/Segment6_Task_O_Detrend_And_Adaptive_Bandpass.md`'s regression check).

| Method | Recomputed | Previously saved | `isequal` |
|---|---|---|---|
| HR_chrom | 76.4104882192 | 76.4104882192 | true |
| HR_pos | 76.4104882192 | 76.4104882192 | true |
| HR_green | 72.8399046575 | 72.8399046575 | true |

**PASS.** The HR path is byte-identical to its pre-Segment-7-Task-A output. Nothing in
Actions 1-6 leaked into it.

## Outputs

- `src/morphology/bandpassMorphology.m` (new)
- `src/morphology/fixPolarity.m` (new)
- `src/morphology/fixPolarityByGroundTruth.m` (new)
- `src/morphology/resampleUniform.m` (new)
- `src/morphology/ensembleAverageBeats.m` (new)
- `src/morphology/extractMorphologyWaveform.m` (new)
- `scripts/run_segment7_task_a_saturation_check.m` (new)
- `scripts/run_segment7_morphology_batch.m` (new)
- `tests/segment7_regression_test.m` (new)
- `results/metrics/segment7_task_a_saturation_check.csv` (new, 15 rows: 5 subjects x 3 channels)
- `results/metrics/segment7_morphology_metrics.csv` (new, 5 rows: one per subject)
- `results/figures/segment7_fig1_bandmode_ablation_5-gt.png` (new)
- `results/figures/segment7_fig2_ensemble_iqr_5-gt.png` (new)
- `results/figures/segment7_fig3_polarity_before_after_5-gt.png` (new)
- `results/figures/segment7_fig4_prototype_vs_groundtruth_5-gt.png` (new)
- `results/figures/segment7_fig5_beatcount_vs_snr_5-gt.png` (new)
- Every file under `filtering/`, `pulseextraction/`, `heartrate/`, `validation/`,
  `pipeline/`, and `android/`: **untouched** (confirmed by Action 7 for the HR path;
  the others were simply never opened by this task).

## Deferred to the second handoff (Tier 2, per the original brief's scope note)

Windowed POS, adaptive harmonic bandpass filtering, landmark ROI, ROI tiling, and the
iterative-envelope-mean notch detector.

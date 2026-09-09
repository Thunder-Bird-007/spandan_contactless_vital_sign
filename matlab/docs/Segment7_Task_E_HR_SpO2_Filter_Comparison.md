# Segment 7 Task E: HR/SpO2 Filtering A/B Comparison

## What this is

A purely classical-DSP A/B test: does swapping the filtering stage from
`filtering/bandpassClean.m` to `filtering/detrendSignal.m` ->
`morphology/bandpassMorphology.m('wide')`-derived-f0 ->
`morphology/adaptiveHarmonicFilter.m` (per-channel, pre-CHROM/POS -- the
same operating point already validated for notch morphology in Task B
branch-2 / Task C2) change **HR or SpO2 accuracy**, on the exact same
validated methodology and datasets already used for this project's
reported HR and SpO2 numbers?

This was evaluated **only** for notch-morphology visibility before now
(`Segment7_Task_A_Morphology_Pipeline.md`, `Segment7_Task_B_Notch_Quantification.md`
-- 4/5 UBFC subjects pass notch detection vs 1/5 baseline). It had never
been run through the HR/SpO2 accuracy pipeline. This task closes that gap.

New script: `matlab/scripts/run_segment7_task_e_hr_spo2_filter_compare.m`
(additive; does not modify any pipeline function -- see Provenance and
Protected-files verification below).

## Provenance of the two baseline numbers this task regression-checks against

Traced directly from source before writing any new code (an earlier draft
of this task incorrectly assumed both numbers came from
`validation/runLOSO.m` on a pooled UBFC+VIPL scope -- corrected here):

- **HR full-pool numbers** (`results/metrics/segment6_hr_pooled_metrics.csv`,
  produced by `matlab/scripts/run_segment6_validation.m`): pooled UBFC
  (N=5, `run_segment4_heartrate_batch.m`) + VIPL v1 (N=107,
  `run_vipl_integration_batch.m`), evaluated **directly** via
  `validation/computeMetrics.m` -- **no `validation/runLOSO.m`, no
  leave-one-out loop of any kind**, because `heartrate/fftHeartRate.m` has
  no fitted parameter to leak between subjects (`run_segment6_validation.m`'s
  own header comment). CHROM: MAE 9.0969 / RMSE 18.0047 / r=0.31448. POS:
  MAE 8.6795 / RMSE 16.4537 / r=0.28091.
  (Note: an older, now-corrected README/android-docs figure of "r=0.957,
  MAE~3.8bpm" was a stale N=8 subpool from early in Segment 6, superseded
  as VIPL grew to its current N=107 -- see `docs/Segment6_Refinement_Notes.md`.
  Not used here.)
- **SpO2 MAE 1.908 number** (`matlab/docs/SpO2_Final_Report_Section.md`,
  produced by `matlab/scripts/run_segment5_final_spo2_report.m`): **VIPL
  v1 ONLY (N=107, source1+source2 pooled)**, via
  `validation/runLOSOStratified.m` (per-dataset stratified LOSO). Not
  pooled with UBFC. MAE 1.9078 / RMSE 5.4303 / r=-0.3333.

## Method

Both conditions reuse the SAME already-cached raw traces
(`data/processed/<subjectID>_rgb_traces.mat`, `roi/extractROISignals.m`'s
own unmodified output) and the SAME already-computed ground truth
(`segment4_hr_summary*.csv` / `segment5_vipl_calibration.csv`) -- no video
re-decode, no ground-truth loader re-invoked.

- **(a) baseline**: `detrendSignal` -> `bandpassClean` -> `chromCombine`/
  `posCombine` -> `bandpassClean` (again, on the combined pulse -- matches
  `run_segment4_heartrate_batch.m`/`run_vipl_integration_batch.m` exactly)
  -> `fftHeartRate`. SpO2's R value: `ratioOfRatios` on this same
  bandpassClean-filtered AC / raw DC.
- **(b) candidate**: `detrendSignal` -> per-channel `adaptiveHarmonicFilter`
  (6 harmonics), f0 estimated once per subject from a
  `bandpassMorphology('wide')` + `chromCombine` + `fftHeartRate` pulse and
  shared across R/G/B -- **exactly** the operating point established in
  `run_segment7_task_b_branch2_batch.m` / `run_segment7_task_c2_true_combined_batch.m`
  (Task C2's corrected position: substitutes for `bandpassMorphology`
  *before* CHROM/POS, per-channel, not applied after). No second filtering
  pass after combination -- straight to `fftHeartRate`. SpO2's R value:
  `ratioOfRatios` on this harmonic-filtered AC / raw DC (the natural
  extension of the same substitution to the SpO2 stage).

HR pool: UBFC (N=5) + VIPL v1 (N=107) = 112, pooled directly (no LOSO), CHROM
and POS both evaluated. SpO2 pool: VIPL v1 only (N=107), `runLOSOStratified`.

112/112 subjects succeeded under both conditions -- **zero failures, zero
NaNs, zero crashes.**

## Results

### HR (`results/metrics/segment7_task_e_hr_filter_comparison.csv`)

| Method | Condition | Scope | N | MAE | RMSE | Pearson r |
|---|---|---|---|---|---|---|
| CHROM | (a) baseline | pooled | 112 | 9.0969 | 18.0047 | 0.31448 |
| CHROM | (b) candidate | pooled | 112 | **11.9650** | **24.1391** | 0.32999 |
| CHROM | (a) baseline | UBFC | 5 | 3.7723 | 6.1541 | 0.94019 |
| CHROM | (b) candidate | UBFC | 5 | 3.7723 | 6.1541 | 0.94019 |
| CHROM | (a) baseline | VIPL | 107 | 9.3458 | 18.3724 | 0.27755 |
| CHROM | (b) candidate | VIPL | 107 | **12.3478** | **24.6608** | 0.29919 |
| POS | (a) baseline | pooled | 112 | 8.6795 | 16.4537 | 0.28091 |
| POS | (b) candidate | pooled | 112 | **14.0055** | **30.5724** | **0.13455** |
| POS | (a) baseline | UBFC | 5 | 3.7723 | 6.1541 | 0.94019 |
| POS | (b) candidate | UBFC | 5 | 3.6703 | 5.9330 | 0.94580 |
| POS | (a) baseline | VIPL | 107 | 8.9089 | 16.7811 | 0.21745 |
| POS | (b) candidate | VIPL | 107 | **14.4884** | **31.2523** | **0.09536** |

**Verdict: the candidate filtering HURTS HR accuracy, clearly and
substantially, on both methods.** Pooled MAE rises 32% for CHROM (9.10 ->
11.97 bpm) and 61% for POS (8.68 -> 14.01 bpm); RMSE roughly doubles for
both. Pearson r is a mixed, much smaller signal: CHROM's r ticks up very
slightly (0.314 -> 0.330), POS's r collapses by more than half (0.281 ->
0.135). UBFC (N=5, clean webcam data, resting subjects) is nearly
untouched -- CHROM is bit-for-bit identical between conditions for all 5
UBFC subjects, POS changes by under 0.1 bpm MAE. **The damage is entirely
on VIPL** (the 107 subjects that dominate the pool), where MAE/RMSE both
increase sharply for both methods.

Looking at individual subjects explains why: several VIPL subjects under
condition (b) show classic **octave errors** -- the harmonic-comb filter
occasionally causes `fftHeartRate`'s peak-pick to lock onto a harmonic bin
instead of the fundamental (e.g. `VIPL_p3_v1_source1` CHROM: 69.4 bpm (a)
vs 140.8 bpm (b), almost exactly 2x; `VIPL_p22_v1_source1` POS: 112.5 bpm
(a) vs 217.3 bpm (b), a physiologically implausible reading still inside
`fftHeartRate`'s valid 42-240 bpm search band, so not a NaN/crash, just a
wrong answer). This is a real, understandable failure mode of narrowing
the passband around a single-source f0 estimate on noisier VIPL video --
not a coding bug (see Protected-files verification below) and not
something this task modifies to "fix," per Action 4/6's scope. It is the
mechanism behind the aggregate MAE/RMSE regression above, reported here
plainly rather than papered over.

### SpO2 (`results/metrics/segment7_task_e_spo2_filter_comparison.csv`)

| Condition | Scope | N | MAE | RMSE | Pearson r |
|---|---|---|---|---|---|
| (a) baseline | VIPL | 107 | 1.9078 | 5.4303 | -0.33336 |
| (b) candidate | VIPL | 107 | 1.9309 | 5.4422 | -0.17452 |

**Verdict: statistically indistinguishable from baseline on MAE/RMSE --
neither helps nor hurts in any way that matters.** MAE moves by +0.023
(1.21% relative), RMSE by +0.012 (0.22% relative) -- both well within
what should be treated as noise at this pool size, not a real effect
either direction. Pearson r moves from -0.333 to -0.175 (smaller in
magnitude, i.e. closer to zero) -- but per `SpO2_Final_Report_Section.md`'s
own established framing, this calibration's Pearson r is already
wrong-signed and does not beat the trivial training-mean baseline on
MAE regardless of condition, so a smaller-magnitude negative r is not
evidence of a real improvement, just a smaller version of the same weak,
already-flagged signal. **The standing verdict on SpO2 (not approved,
weak, wrong-sign) is unchanged by this filtering swap.**

## Protected-files verification (Action 4)

SHA-256 of all ten protected files plus `filtering/detrendSignal.m` and
`validation/runLOSOStratified.m` (also exercised by this task, though not
in the original protected list), hashed immediately before writing any new
code and again after the full run completed: **byte-identical, confirmed
by direct diff, zero differences.** `filtering/bandpassClean.m`,
`morphology/bandpassMorphology.m`, `morphology/adaptiveHarmonicFilter.m`,
`pulseextraction/chromCombine.m`, `pulseextraction/posCombine.m`,
`heartrate/fftHeartRate.m`, `spo2/ratioOfRatios.m`, `spo2/calibrateSpO2.m`,
`validation/runLOSO.m`, `validation/runLOSOStratified.m`,
`validation/computeMetrics.m`, `roi/extractROISignals.m`,
`filtering/detrendSignal.m` were not modified.

## Bottom line

For the report: swapping in the Task C2 harmonic-comb filtering
(validated for dicrotic-notch morphology) at the HR/SpO2 accuracy stage is
a **net negative for HR** (substantially worse MAE/RMSE on both CHROM and
POS, driven by VIPL-side octave errors, with no meaningful accuracy
compensation from the small r changes) and **a wash for SpO2** (no real
change either direction, still not report-ready for the reasons already
established). The two use cases -- notch morphology vs HR/SpO2 accuracy --
call for different filtering choices at this operating point; there is no
single filtering stage that wins at both, at least not this one.

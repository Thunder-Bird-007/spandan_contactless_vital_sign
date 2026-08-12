# Segment 6 Task K: v7 (After-Exercise) Scenario Integration

Companion to `docs/Segment6_Refinement_Notes.md` (Tasks A-J) and
`docs/VIPL_Scenario_Coverage.md` (the recon this task acts on) — this is an
ADDITION (Task K), not a rewrite. Tasks A-J's numbers are left exactly as
they were.

Why v7: `VIPL_Scenario_Coverage.md` found v7 (after-exercise) is the only
VIPL-HR scenario whose ground-truth HR distribution meaningfully differs
from v1 (cleaned mean 75.4 -> 98.6 bpm, std 10.1 -> 16.7, range extends to
157 bpm). SpO2 barely moves across scenarios and was explicitly not chased
further here.

## 0. Action 1 — loader generalization

`io/loadVIPLVideo.m` and `io/loadVIPLGroundTruth.m` were inspected line by
line before touching anything. Both already take `scenarioNum` as an
explicit third argument and build `v<scenarioNum>` into the path — neither
hardcodes v1 anywhere. **No code changes were needed or made to either
file.** `roi/extractROISignals.m`, `filtering/detrendSignal.m`,
`filtering/bandpassClean.m`, `pulseextraction/chromCombine.m`,
`pulseextraction/posCombine.m`, `heartrate/fftHeartRate.m`,
`spo2/ratioOfRatios.m`, and `spo2/calibrateSpO2.m` were likewise left
completely untouched, per the constraint — none of them are scenario-aware
and none needed to become so.

## 1. v7 extraction and batch coverage

**Data was not extracted locally before this task** — `data/raw/VIPL-HR/`
only had v1 on disk. v7/source1 (or source2 where source1 is absent) was
extracted directly from the 21 `VIPL-HR-V1/data/*.zip` archives for every
subject the coverage matrix marks as having v7, using the same
source1-primary/source2-fallback rule already used for v1. p56 (no v6-v9
at all) was excluded from the extraction.

| Expected (recon) | Extracted | Match |
|---|---|---|
| source1: 91 | 91 | yes |
| source2 fallback: 15 (106 total - 91 source1) | 15 | yes |
| Total v7 subjects: 106 (p56 excluded) | 106 | yes |

`scripts/run_vipl_v7_integration_batch.m` ran all 106 subjects through
Segments 2-5 (ROI -> detrend -> bandpass -> CHROM/POS/green -> FFT HR,
plus ratio-of-ratios -> leave-one-out SpO2 calibration). **106 of 106
subjects succeeded, 0 failures.** Outputs:
`results/metrics/segment4_hr_summary_v7.csv` (106 rows, new file, same
schema as `segment4_hr_summary.csv`/`segment4_hr_summary_vipl.csv` plus a
trailing `scenario` column) and `results/metrics/segment5_v7_calibration.csv`
(106-fold leave-one-out SpO2 calibration, mean abs error 2.78 percentage
points — noticeably worse than v1's 1.91, see Section 3 for why).

## 2. Action 3 — fault-code stripping

HR==255 and SpO2 in {44, 127+} were stripped from `gt.hr`/`gt.spo2`
per-subject, before `mean()`, inside the batch script itself (not a
separate pass) so `HR_groundtruth`/`SpO2_true` never include fault
samples. Checked against the actual extracted source1/source2 data (per
Action 3's instruction, since recon read a source-priority file that may
not match what this batch actually pulled) rather than assumed from
recon:

| Subject | Recon flagged? | Confirmed here? | Fault samples stripped |
|---|---|---|---|
| p24 | yes | yes | 10 |
| p75 | yes | yes | 28 |
| p85 | yes | yes | 23 |
| p90 | yes | yes | 8 |
| p94 | yes | yes | 13 |

All 5 recon-flagged subjects confirmed exactly, no new ones found, no
false positives. 5 of 106 v7 subjects (4.7%) hit fault codes — in line
with recon's "roughly 5-6%" estimate.

**A real finding beyond what the {44, 127+} rule alone catches**: p75 and
p85's raw `gt_SpO2.csv` traces are not "mostly valid readings with a few
127-spikes," the way p24/p90/p94 are. p75's entire 40-sample trace sits at
44-46 (24 samples are exactly 44, the rest 45-46); p85's entire 33-sample
trace sits at 44-45. The specified stripping rule only removes the literal
44s, so p75's "cleaned" `SpO2_true` still comes out to 45.5% and p85's to
45% — physiologically impossible values (no live subject has 45% SpO2),
just a sensor stuck at its floor for the whole clip rather than spiking to
a single fault code. This shows up downstream as the two largest
leave-one-out SpO2 errors in `segment5_v7_calibration.csv` (p75: abs_error
= 50.4, p85: abs_error = 50.9 percentage points) — both are the sensor
being wrong for the entire recording, not a calibration failure. This
report flags it rather than silently widening the fault rule beyond what
was specified; per the Task K SpO2 scope decision (Section 4), this does
not feed into any pooled metric this task actually computes, so it was
left as-is rather than patched.

## 3. Pooled vs v1-only HR metrics (Action 4, Part 1)

`scripts/run_segment6_task_k_pooled_v1_v7.m` pooled
`segment4_hr_summary.csv` (UBFC, N=5) + `segment4_hr_summary_vipl.csv`
(VIPL v1, N=107) = 112 v1-equivalent subjects, then added the 106 v7
subjects for N=218 pooled.

| Method | Scope | N | MAE | RMSE | Pearson r |
|---|---|---|---|---|---|
| CHROM | v1-only | 112 | 9.10 | 18.00 | 0.314 |
| CHROM | v1+v7 pooled | 218 | 12.29 | 20.43 | 0.399 |
| POS | v1-only | 112 | 8.68 | 16.45 | 0.281 |
| POS | v1+v7 pooled | 218 | 11.36 | 18.69 | 0.496 |
| Green | v1-only | 112 | 14.98 | 19.49 | 0.087 |
| Green | v1+v7 pooled | 218 | 22.82 | 30.27 | 0.047 |

Honest reading: adding v7 makes every method's MAE/RMSE worse in absolute
terms (as expected — after-exercise HR is harder to read: faster rates,
more motion, wider spread), but Pearson r goes UP for CHROM and POS (0.314
-> 0.399, 0.281 -> 0.496). That is not a contradiction: v7 widens the true
HR range far beyond v1's narrow 47-104 bpm band, and a wider ground-truth
range makes it easier for an estimator to track the *relative* ordering of
subjects correctly even while its *absolute* error grows — exactly the
same "N=18->N=112 broadens range, error grows, correlation improves"
pattern already documented for the original v1 pooling in
`Segment6_Refinement_Notes.md`. Green-only degrades far more sharply than
CHROM/POS (MAE nearly 1.5x worse, r collapses to near zero) — consistent
with it already being the weakest method on v1 and having no chrominance
compensation to fall back on when motion/exercise artifacts increase.

## 4. Refit vs. frozen CHROM/POS agreement threshold (Action 4, Parts 2-3)

Task I's 29.27% threshold was derived from the v1-only N=112 pool, whose
disagreement values maxed out around 30-40%. v7 changes that distribution
substantially — pooled max relative disagreement is now **90.08%**, far
beyond anything v1 alone produced.

| | Old (Task I, v1-only) | New (Task K, refit on v1+v7 pool) |
|---|---|---|
| Threshold | 29.27% | **59.54%** |
| Derivation | second-largest gap in v1-only sorted disagreement | second-largest gap in v1+v7-pooled sorted disagreement |
| Subjects flagged low-confidence | 29/112 (Task I) | 3/218 (1.38%) |
| Switch fires on pooled N=218 | 19/218 (8.72%) | 4/218 (1.83%) |

Scored on the SAME v1+v7 pooled set (N=218), so both numbers are directly
comparable:

| Method | N | MAE | RMSE | Pearson r |
|---|---|---|---|---|
| CHROM alone | 218 | 12.29 | 20.43 | 0.399 |
| POS alone | 218 | 11.36 | 18.69 | 0.496 |
| Switched, old frozen 29.27% threshold | 218 | 11.52 | 19.10 | 0.465 |
| Switched, refit 59.54% threshold | 218 | 11.64 | 19.19 | 0.4655 |

**Honest reading — this is a real change from the v1-only finding, not
just a number update.** On the v1-only pool (Task J), switching beat both
CHROM-alone and POS-alone. On the v1+v7 pool, **POS alone now has the
lowest MAE and RMSE of all four options**, beating both the old-threshold
switch and the new refit-threshold switch. Both switching variants still
beat CHROM-alone, and the refit threshold's higher Pearson r (0.4655 vs
0.465) is a marginal improvement over the old threshold on this pool, but
neither switching variant recovers POS's edge once v7's higher-HR,
higher-disagreement subjects are in the mix. The refit threshold fires far
less often (4 vs 19 subjects) because v7 pushed the "normal" disagreement
band itself upward, so the old 29.27% cutoff now flags many ordinary v7
subjects as low-confidence that the refit threshold correctly leaves alone
— but firing less often does not translate into materially better pooled
accuracy here.

Failure-mode check on the refit-threshold switch: of the 4 subjects it
fired on, 3 were helped (POS error < CHROM error) and 1 was hurt — the
same "usually helps, occasionally doesn't" pattern as Task J's v1-only
check, just at much smaller N.

**Bottom line for the writeup**: once v7 is in the pool, plain POS is the
strongest single HR estimator overall, and the CHROM/POS switching
strategy — whether using the old frozen threshold or the newly refit one —
no longer clearly beats it. This is worth reporting as a genuine finding,
not smoothed over with the switching estimator's earlier v1-only win.

## 5. SpO2 (deliberately not touched)

Per the Task K scope decision, `validation/runLOSO.m` and
`validation/runLOSOStratified.m` were not modified or rerun against v7,
since `VIPL_Scenario_Coverage.md` already established v7's SpO2 spread is
within noise of v1's once fault codes are stripped. `segment5_v7_calibration.csv`
(the batch script's own leave-one-out SpO2 pass, same as
`run_vipl_integration_batch.m` already does for v1) is a byproduct of
running Segment 5, not a new SpO2 validation pass — its inflated 2.78-point
mean error is fully explained by the two fully-faulted-sensor subjects in
Section 2 (p75, p85), not by v7 broadly being harder for SpO2.

## 6. Summary vs. verification targets

- v7 extraction success: **106/106 subjects processed, 0 failures** —
  matches the expected 91 (source1) + 15 (source2 fallback) = 106
  coverage from `VIPL_Scenario_Coverage.md` exactly, p56 correctly
  excluded.
- Fault-code subjects: **p24, p75, p85, p90, p94** — all 5 recon-predicted
  subjects confirmed against the real extracted data, no surprises, plus
  one additional finding (p75/p85's fault range extends past the literal
  44/127 codes into 45-46, see Section 2).
- Pooled vs v1-only HR (CHROM/POS/switched): MAE/RMSE worsen, Pearson r
  improves, when v7 is added — see Section 3 table.
- Old-threshold-vs-refit-threshold: 29.27% -> **59.54%**, switch-fire rate
  drops from 19 to 4 subjects on the pooled set, and POS-alone overtakes
  both switching variants once v7 is in the pool — see Section 4 table.

## Outputs

- `data/raw/VIPL-HR/p*/v7/source{1,2}/` — 106 subjects' worth of newly
  extracted video/ground-truth (~8.2 GB).
- `scripts/run_vipl_v7_integration_batch.m` (new)
- `scripts/run_segment6_task_k_pooled_v1_v7.m` (new)
- `results/metrics/segment4_hr_summary_v7.csv` (new, 106 rows)
- `results/metrics/segment5_v7_calibration.csv` (new, 106 rows)
- `results/metrics/segment6_hr_pooled_metrics_v1_v7.csv` (new)
- `results/metrics/segment6_hr_agreement_flags_v1_v7.csv` (new)
- `results/metrics/segment6_hr_switching_metrics_v1_v7.csv` (new)
- `results/figures/VIPL_p*_v7_source*_roi_sanity.png`,
  `..._filtering_sanity.png`, `..._heartrate_sanity.png` (106 subjects x 3)
- `results/figures/segment5_v7_calibration_scatter.png`
- `results/logs/vipl_v7_batch_run.log`, `results/logs/segment6_task_k_run.log`

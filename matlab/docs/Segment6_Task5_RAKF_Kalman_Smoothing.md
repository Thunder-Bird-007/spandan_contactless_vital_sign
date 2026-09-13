# Segment 6 (Action 5) — Residual/Quality-Adaptive Kalman Smoothing (RAKF)

Per Debnath & Kim (*PLOS ONE* 2026, 21(1):e0340097), implements RAKF — a random-walk state
model on the HR estimate, residual-adaptive measurement-noise covariance, and a
signal-quality-weighted update — and compares it head-to-head against Task P/Q's existing
windowed-consistency methods (`docs/Segment6_Task_P_Windowed_Harmonic_Quality.md`,
`docs/Segment6_Task_Q_Anchored_Continuity_And_2Way_Switching.md`, read first, not
re-derived here), on the SAME 107-subject VIPL pool and the SAME per-window
candidates/quality scores those tasks used.

## Method

New file `validation/residualAdaptiveKalmanHR.m`. State: `x_k = x_{k-1} + w_k` (random
walk). Measurement: `z_k = x_k + v_k`. Residual-adaptive noise: `R_k = R0*(1 +
|innovation|/beta)` — a measurement far from the current prediction is trusted less.
Quality-weighted: `R_k_effective = R_k / max(qualityScore(k), eps)` — a spectrally messy
window (low `windowedHeartRate.m` quality score) is trusted less too. Standard scalar
Kalman gain/update from there. **Honesty note, stated up front in the file's own header**:
this implements the MECHANISM the paper describes, not a verbatim reproduction of its own
Eq. 9-18 (not independently available to check numeric constants against) — `R0`, `beta`,
and `Q` are this implementation's own data-derived defaults (`R0 = var(measurements)`,
`beta = std(measurements)`, `Q = 1 bpm^2/window`), not values copied from the paper.

`scripts/run_segment6_task5_rakf_batch.m`: reuses the exact same cached
`_rgb_traces.mat`/`_filtered_traces.mat` and `heartrate/windowedHeartRate.m` output Task
P/Q used (no video reprocessing). Task P/Q's own five method columns are read directly
from `results/metrics/segment6_task_q_anchored_windowed_hr_summary.csv` (not recomputed);
RAKF is computed fresh from each subject's own `candidateBpm(:,1)` (tallest-peak-per-window
sequence) and `qualityScore`. 107/107 VIPL subjects usable, 0 failures; 112/112 pooled
subjects usable, 0 failures.

## Head-to-head, 107-subject VIPL pool (`results/metrics/segment6_task5_rakf_vipl107_metrics.csv`)

| Method | N | MAE | RMSE | Pearson r |
|---|---|---|---|---|
| Whole-clip single FFT (baseline) | 107 | 9.346 | 18.372 | **0.278** |
| **Naive windowed (no gating, no continuity)** | 107 | **10.338** | **15.643** | 0.316 |
| Gating only | 107 | 10.383 | 15.663 | **0.317** |
| Gating + continuity (Task P, window-1 anchor) | 107 | 12.466 | 21.575 | 0.237 |
| Gating + anchored continuity (Task Q) | 107 | 10.621 | 19.421 | 0.205 |
| **RAKF (this task, NEW)** | 107 | 12.148 | 22.040 | **0.204** |

## Pooled 112 generalization (`results/metrics/segment6_task5_rakf_pooled112_metrics.csv`)

| Method | N | MAE | RMSE | Pearson r |
|---|---|---|---|---|
| Whole-clip CHROM baseline | 112 | **9.097** | **18.005** | **0.314** |
| RAKF (this task, NEW) | 112 | 11.827 | 21.591 | 0.255 |

## Verdict — which one actually wins, stated plainly

**RAKF does not win anywhere it was tested.** On the 107-subject VIPL pool, RAKF's MAE
(12.15) and RMSE (22.04) are both the WORST of all six methods compared, and its Pearson
r (0.204) is the lowest of all six too — worse than the simple whole-clip baseline, worse
than naive windowing, worse than gating alone, and roughly tied with (MAE) or worse than
(RMSE, r) Task P's own window-1-anchored continuity, which Task P itself already
identified as a regression. On the pooled 112, RAKF (MAE 11.83) is also worse than the
plain whole-clip CHROM baseline (MAE 9.10).

**The best-performing methods on this pool remain the simplest ones**: naive windowing
and gating-only, both of which beat every continuity-based method (Task P's, Task Q's,
and RAKF) on RMSE and Pearson r. Averaging several independent per-window FFT reads
(naive windowing's own mechanism) continues to be the single most effective intervention
found across Segment 6 Task P/Q/5 combined — every attempt to add temporal-consistency
logic on top of it (window-1 continuity, quality-anchored continuity, now Kalman
smoothing) has made pooled accuracy worse, not better, on this specific data.

**Caveat on RAKF specifically, stated honestly rather than concluding the mechanism is
inherently bad**: this implementation's `R0`/`beta`/`Q` are self-derived defaults, not
values taken from Debnath & Kim's own paper (not independently verified against it — see
Method above). It is plausible a differently-tuned RAKF (e.g. a smaller `Q` forcing
slower adaptation, or a `beta` scaled differently) performs better; this result is
specific to the defaults implemented here, not a proof that residual/quality-adaptive
Kalman filtering categorically cannot help this pool. What CAN be said with confidence:
with this implementation's reasonable, data-derived defaults, RAKF does not beat any of
Task P/Q's existing methods, and does not beat the simple whole-clip baseline either.

## Bottom line

Do not adopt RAKF over the existing methods on this evidence. If pursued further, the
next step would be a parameter sweep over `R0`/`beta`/`Q` on this same pool before
concluding the mechanism itself doesn't help — not attempted here, out of scope for this
task's head-to-head comparison.

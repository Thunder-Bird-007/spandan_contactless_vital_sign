# Segment 9 (Action 2) — RAKF Parameter Sweep, Small Pool

Exploratory pilot from the Spandan Field Guide's "still open" list. **Feasibility/
direction-finding only, SMALL sample on purpose (10 of 107 VIPL subjects) — not a full
validation pass, not to be scaled to the full pool without asking first.** Does not
modify `validation/residualAdaptiveKalmanHR.m` — only varies the `opts` struct it
already accepts.

## Step 1 — checking the paper's own recommended parameter values (not done before)

`docs/Segment6_Task5_RAKF_Kalman_Smoothing.md` stated up front that its `R0`/`beta`/`Q`
defaults were this implementation's own data-derived choices, explicitly **not**
checked against Debnath & Kim's paper ("not independently available to check numeric
constants against" — that session's own words). This pilot fetched the actual paper
(PMC12818640, "Advanced signal-processing framework for remote photoplethysmography-based
heart rate measurement: Integrating adaptive Kalman filtering with discrete wavelet
transformation," PLOS ONE 2026) and found real numbers, plus a genuine mechanism
mismatch worth flagging honestly rather than quietly working around:

- **Eq. 12 uses an EXPONENT, not this implementation's DIVISION**: the paper's
  `R_k^adaptive = R0 * (1 + |innovation|^beta)` vs. this implementation's
  `R_k = R0 * (1 + |innovation| / beta)`. This is a real mechanism difference between
  the port and the paper, discovered here for the first time. **Not fixed in this
  pilot** — re-deriving the filter itself is more than "check the sweep ranges," it's a
  separate task; flagged here as a finding for a possible future one.
- The paper fixes **R0 = 25 (bpm²)** and **Q_k = 2×10⁻⁴ (bpm²)** across all its
  datasets, both applied **per video frame at 30fps (~33ms/step)** — structurally
  different from this implementation's per-5-SECOND-HOP window state update
  (`residualAdaptiveKalmanHR.m`'s own header). Since a random-walk process-noise
  variance scales roughly linearly with elapsed time, the paper's per-frame `Q_k` was
  approximated to a per-window value by scaling by frames-per-window (150 frames per 5s
  hop at a nominal 30fps): `0.03 = 2e-4 * 150`. Stated as an approximation, not an exact
  unit conversion — the paper does not give enough detail on its own per-frame
  smoothing/decimation to do better than this.
- **Beta has no explicit numeric default in the paper** — its own sensitivity analysis
  (Fig. 7) says results are "robust" to it, with a marginal (<0.3bpm) effect. Swept as a
  multiplier on this implementation's own data-derived default (`std(measurementBpm)`)
  instead, since the paper gives nothing sharper to anchor to.
- The paper's separate **Eq. 15 weighting factor α (0.1–0.6 stable range, degrading
  beyond 0.7)** is a DIFFERENT parameter from Eq. 12's β — it weights signal-quality,
  not residual-adaptivity — and does not map onto anything in this implementation's own
  three-parameter (`R0`/`beta`/`Q`) formulation. Not swept here, noted only so it isn't
  confused with `beta` above.

## Method

New `scripts/run_segment6_task5b_rakf_param_sweep_pilot.m`. 10 subjects: VIPL p1-p10
(v1/source1), reusing the SAME cached `data/processed/<id>_rgb_traces.mat` /
`_filtered_traces.mat` Task P/Q/5 already used — no new video reprocessing. Sweep grid
(still using this implementation's own division-based formula, per the mismatch noted
above — this pilot sweeps parameters, it does not change the model): `R0` ∈ {5, 10, 25
(paper), 50}, `Q` ∈ {2e-4 (paper, literal), 0.03 (paper, per-window-scaled), 0.1, 1
(current default's order of magnitude)}, `beta` as a multiplier on each subject's own
`std(measurementBpm)` ∈ {0.5, 1, 2} — 48 combinations, cheap (scalar Kalman filter over a
handful of windows per subject, no video decode).

Output: `results/metrics/segment6_task5b_rakf_sweep_pilot.csv` (48 rows, one per grid
combo, pooled MAE/RMSE/r across the 10-subject sample).

## Result

| | R0 | Q | beta mult. | N | MAE | RMSE | r |
|---|---|---|---|---|---|---|---|
| Current default, this 10-subject sample | (per-subject `var`) | 1 | (per-subject `std`) | 10 | 5.22 | 6.48 | 0.886 |
| **Best sweep combo** | 5 | 1 | 2 | 10 | **4.80** | **5.88** | **0.909** |
| Worst sweep combo | 5/10/25/50 | 0.0002 | 0.5 | 10 | 5.35 | 6.69 | 0.879 |

Full 48-row grid: `results/metrics/segment6_task5b_rakf_sweep_pilot.csv`.

**Reference points, NOT to be beaten on N=10 — directional comparison only, quoted from
`docs/Segment6_Task5_RAKF_Kalman_Smoothing.md`'s full-107-subject numbers**: RAKF default
MAE 12.148/RMSE 22.040/r 0.204; naive-windowed (the best simple method found so far) MAE
10.338/RMSE 15.643/r 0.316; whole-clip baseline MAE 9.346/RMSE 18.372/r 0.278. This
10-subject sample's own current-default MAE (5.22) is already far better than the
full-107 number (12.15) simply because p1-p10 happen to be an easier subset on average —
this is exactly why the task calls for a directional, same-sample comparison rather than
treating any N=10 number as comparable to the full pool.

**The paper-informed Q values (2e-4, 0.03) did NOT win.** The best combo used `Q=1` (this
implementation's own existing default order of magnitude), a small `R0=5`, and a LARGER
`beta` (2x default). All three of those changes push the filter in the SAME direction:
trust each new measurement MORE and smooth LESS (small R0 = measurements trusted more by
default; large Q = state uncertainty grows faster between windows, again favoring the
new measurement; large beta = a given residual inflates R_k less aggressively, so even a
surprising measurement isn't down-weighted as hard). That is the same direction this
project's entire Segment 6 Task P/Q/5 history already points: the simplest,
least-smoothed methods (naive windowing, gating-only) consistently beat every
continuity/Kalman-based method tried. The sweep's own best point is, in effect, "make
RAKF behave as close to un-smoothed as this model allows."

## Verdict: **no** (sweep does not rescue RAKF)

The best swept configuration only modestly improves over the current default on this
10-subject sample (MAE 5.22 → 4.80, ~8% relative) — a real but small effect, and in a
direction that CONFIRMS rather than overturns Task 5's original finding rather than
reversing it: the tuning that helps most is the tuning that makes RAKF act least like a
Kalman filter and most like "just trust the raw measurement." This does not suggest a
differently-tuned RAKF would leapfrog past naive windowing or gating-only on the full
pool — it suggests RAKF's own smoothing mechanism is the thing costing it accuracy on
this data, consistent with (not a new finding contradicting) the original verdict. The
genuinely new, useful output of this pilot is the mechanism-mismatch finding (Eq. 12
exponent vs. this port's division) — worth a look in any future RAKF work — not a
parameter combination worth adopting.

## Do not scale up

Per this task's own instruction: this 10-subject, 48-combo sweep is NOT to be scaled to
the full 107/112-subject pool without asking first. If a future session wants to check
whether the "less smoothing" direction holds at full scale, that is a new, explicit
decision to make, not an automatic next step from this pilot.

## Files added

- `matlab/scripts/run_segment6_task5b_rakf_param_sweep_pilot.m` — new, additive. Does
  not modify `validation/residualAdaptiveKalmanHR.m` or
  `scripts/run_segment6_task5_rakf_batch.m`.
- `results/metrics/segment6_task5b_rakf_sweep_pilot.csv`.
- This file.

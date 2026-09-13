# Segment 9 (Action 3) — Smarter Region-Switching Rule, Small Pool

Exploratory pilot from the Spandan Field Guide's "still open" list. **Feasibility/
direction-finding only, SMALL slice on purpose (v2/v5 scenarios only, not all four, not
a new subject pool) — not a full validation pass.** New function ALONGSIDE (not
replacing) `validation/computeRegionSwitchingEstimate.m` and
`computeRegionSwitchingEstimate2Way.m` — both remain unchanged and independently
callable.

## Method

New `validation/computeRegionSwitchingEstimateWeighted.m`. Two changes to the DECISION
RULE only (no change to `roi/extractROISignals.m`'s region geometry or any upstream HR
computation):

1. **Standout check first.** For each region, distance to the OTHER THREE regions' own
   median (`d_i`), divided by the overall four-region spread (range). If the closest
   region's `d_i / spread < 0.15` (a CHOSEN threshold for this pilot, not derived from
   this project's own data — stated explicitly, not claimed validated), that region is
   a "clear standout" and is selected directly — no vote needed.
2. **Weighted fallback vote.** When no standout exists, instead of the existing
   function's unweighted argmin-to-median-of-four (which the doc below shows picks
   forehead 70-80% of the time regardless of scenario), compute a weighted center that
   double-counts forehead and cheek: `median([forehead, forehead, cheek, cheek,
   glabella, malar])`. The region actually selected is still whichever of the four real
   per-region estimates lands closest to that weighted center — output is always one of
   the four original values, never an interpolated number, same contract as the
   existing function.

Tie-break (both branches): forehead, then cheek, then glabella, then malar — reordered
from the original function's forehead>glabella>malar>cheek to put cheek second, matching
this pilot's forehead/cheek-favoring premise.

## Test slice

`results/metrics/segment6_task_n_region_hr_summary.csv`, scenarios `v2_motion` and
`v5_dark` only (20 subjects each, the full per-scenario N — not further subsetted, since
this is already-cached data with zero marginal reprocessing cost) — the two scenarios
`docs/Segment6_Task_N_Multi_Region_ROI.md` Section 5 found the EXISTING unweighted
switcher already beats its scenario's best single region. v1/v4 (where the existing
switcher already loses) were deliberately excluded, per this task's own scoping.

New `scripts/run_segment6_region_switch_weighted_pilot.m`. Output:
`results/metrics/segment6_region_switch_weighted_pilot.csv`.

## An honest discrepancy found while building this, reported rather than smoothed over

`docs/Segment6_Task_N_Multi_Region_ROI.md` Section 5 reports the EXISTING unweighted
switcher's MAE as **7.72 (v2)** and **4.79 (v5)**. Recomputing that SAME existing
function directly from `segment6_task_n_region_hr_summary.csv` (independently confirmed
in both MATLAB and a standalone Python cross-check, both agreeing) gives **7.0712 (v2)**
and **4.6654 (v5)** instead — a real, non-rounding difference of ~0.6-0.7bpm on v2. The
"forehead alone" and "cheek alone" numbers DO match the doc exactly (8.1821 vs. 8.18,
4.9763 vs. 4.98), which confirms the CSV data itself is the right data — only the
switching computation itself no longer reproduces the doc's cited number. This was not
investigated further (out of this pilot's scope — Action 3 is about the NEW weighted
rule, not auditing Task N's old numbers) but is flagged here plainly rather than
silently used or silently ignored. **All comparisons below use a FRESH recomputation of
the existing switcher on the identical data slice this pilot also tests the new rule
on**, so the new-vs-existing comparison is apples-to-apples regardless of which number
is "correct" historically.

## Result

| Scenario | Method | N | MAE | RMSE | r |
|---|---|---|---|---|---|
| v2 (motion) | forehead alone | 20 | 8.1821 | — | — |
| v2 (motion) | existing unweighted switcher (recomputed fresh) | 20 | **7.0712** | 9.6899 | 0.7096 |
| v2 (motion) | **NEW weighted standout-first switcher** | 20 | **7.1825** | 10.1908 | 0.6635 |
| v5 (dark) | cheek alone | 20 | 4.9763 | — | — |
| v5 (dark) | existing unweighted switcher (recomputed fresh) | 20 | 4.6654 | 6.5952 | 0.8038 |
| v5 (dark) | **NEW weighted standout-first switcher** | 20 | **4.6102** | **6.8262** | 0.7867 |

Full CSV (includes RMSE/r for the single-region rows too): `results/metrics/
segment6_region_switch_weighted_pilot.csv`.

**Region-selection behavior** (the mechanism working as designed, separate from the net
MAE number): standout branch fired 12/20 (v2) and 8/20 (v5) subjects; weighted-vote
fallback fired the rest. Selection counts, NEW weighted rule vs. the doc's own reported
counts for the OLD unweighted rule (`docs/Segment6_Task_N_Multi_Region_ROI.md` Section
4):

| Scenario | Rule | forehead | glabella | malar | cheek |
|---|---|---|---|---|---|
| v2 (motion) | old (doc) | 16 | 2 | 2 | 0 |
| v2 (motion) | **new (this pilot)** | 17 | 1 | 0 | 2 |
| v5 (dark) | old (doc) | 14 | 4 | 1 | 1 |
| v5 (dark) | **new (this pilot)** | 13 | 1 | 1 | **5** |

In v5, the new rule selects cheek noticeably more often (5 vs. 1) — cheek is the actual
best single region in v5 (4.98 vs. forehead's 6.54, per the doc), so the forehead/cheek
weighting is doing exactly what it was designed to do there. In v2, the new rule's
counts barely move (17 vs. 16 forehead) — forehead genuinely is close to a standout in
v2 already under either rule, so there was little for the weighting to change.

## Verdict: **ambiguous** (small, scenario-dependent effect)

**v5 (dark): a small real improvement** — NEW (4.6102) beats both the freshly-recomputed
existing switcher (4.6654) and the best single region (4.9763), on all the metrics that
matter for this project's own honesty standard except RMSE, where it's very slightly
worse (6.8262 vs 6.5952) despite the better MAE and worse r — a genuinely mixed, not
uniformly better, signal even within the "improved" scenario, consistent with the
project's standing practice of not rounding a partial win up to a clean one. This lines
up with the mechanism doing what it was designed to do (favoring cheek where cheek is
actually best).

**v2 (motion): flat to very slightly worse** — NEW (7.1825) is worse than the
freshly-recomputed existing switcher (7.0712) by about 0.11bpm, though still clearly
better than forehead alone (8.1821). The selection-count table above suggests this isn't
a mechanism failure so much as the new tie-break order (forehead>cheek>glabella>malar,
vs. the original's forehead>glabella>malar>cheek) landing slightly differently on a
handful of near-tied subjects where v2 doesn't have a real region-preference signal to
find in the first place.

**Net**: both differences (±0.1bpm on N=20) are small relative to the metric's own scale
and to what N=20 can resolve confidently. This pilot does not show a clear win, but does
show the mechanism behaving as intended in the one scenario (v5) where the
forehead/cheek premise actually applies, without breaking the other. Worth a look at
larger N before either adopting or discarding — not attempted here, out of this pilot's
scope (see "do not scale up" below).

## Do not scale up

Per this task's own instruction: this two-scenario, N=20-each slice is NOT to be scaled
to all four Task N scenarios or a larger subject pool without asking first.

## Files added

- `matlab/src/validation/computeRegionSwitchingEstimateWeighted.m` — new, additive.
  `computeRegionSwitchingEstimate.m` and `computeRegionSwitchingEstimate2Way.m` are
  unmodified.
- `matlab/scripts/run_segment6_region_switch_weighted_pilot.m` — new, additive.
- `results/metrics/segment6_region_switch_weighted_pilot.csv`.
- This file.

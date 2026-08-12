# Segment 6 Task Q — Quality-Anchored Harmonic Continuity + 2-Way Forehead/Cheek Region Switching

Two independent refinements of already-diagnosed flaws, bundled together
because both reuse existing infrastructure and cached data — no new video
extraction or reprocessing for either. Part 1 refines Task P's
window-1-anchored harmonic continuity; Part 2 refines Task N's 4-region
switching estimator. `heartrate/fftHeartRate.m`, `filtering/bandpassClean.m`,
`pulseextraction/chromCombine.m`, `pulseextraction/posCombine.m`,
`heartrate/windowedHeartRate.m`, `roi/extractROISignals.m`'s existing
region-mode geometry, `validation/selectHarmonicConsistentHR.m`,
`validation/computeRegionAgreement.m`, and
`validation/computeRegionSwitchingEstimate.m` are all **unmodified** — every
new mechanism below is new logic layered on top, both old and new versions
staying independently callable.

## Part 1 — Quality-anchored harmonic continuity

### Motivation (Task P's diagnosed flaw)

`validation/selectHarmonicConsistentHR.m` always starts its continuity
chain at window 1 and keeps window 1's tallest peak unconditionally, with
no way to know whether window 1 is *already* harmonic-confused. Task P
found this is the dominant driver of a pool-level regression: continuity
fixed the one motivating case it was built for (`VIPL_p21`, 127.2 → 74.7
bpm against a true 68 bpm) but raised full-pool MAE from 10.34 to 12.47
and dropped Pearson r from 0.32 to 0.24, because a bad first-window choice
propagates forward uncorrected ([[segment6-refinement-findings]]).

### Action 1 — `validation/selectHarmonicConsistentHR_anchored.m`

New function, `selectHarmonicConsistentHR.m` untouched. Instead of always
anchoring at window 1, it anchors at whichever window has the **highest**
`windowedHeartRate.m` quality score in the clip, keeps that window's own
tallest peak, and propagates the same closest-to-previous-chosen-bpm rule
**outward in both directions** — forward through later windows using
`chosenBpm(w-1)` as usual, and backward through earlier windows using
`chosenBpm(w+1)` (the already-decided neighbor closer to the anchor) —
each direction independent of the other.

### Action 2 — Isolated p21 check

Run via `scripts/run_task_q_p21_anchored_check.m`, same isolation
discipline as Task P's own p21 check (no gating, cached traces only).

| Window | Start (s) | Top-3 candidates (bpm) | Quality | Task P (window-1 anchor) chosen | Task Q (quality anchor) chosen | Override (Task Q) |
|---|---|---|---|---|---|---|
| 1 | 0.0 | 66.15, 132.30, 114.26 | 0.0772 | 66.15 | 132.30 | YES |
| 2 (highest quality) | 5.0 | 126.29, 66.15, 84.19 | **0.1071** | 66.15 | 126.29 (ANCHOR) | no |
| 3 | 10.0 | 126.29, 150.35, 48.11 | 0.0750 | 48.11 | 126.29 | no |
| 4 | 15.1 | 126.29, 72.17, 150.35 | 0.0772 | 72.17 | 126.29 | no |
| 5 | 20.1 | 102.24, 150.35, 126.29 | 0.0945 | 102.24 | 126.29 | YES |
| 6 | 25.1 | 96.22, 72.17, 126.29 | 0.0874 | 96.22 | 126.29 | YES |
| 7 | 30.1 | 72.17, 120.28, 132.30 | 0.0912 | 72.17 | 120.28 | YES |

**The anchor is window 2, NOT window 1 on this subject** — window 2 has
the highest quality score (0.1071) of all seven windows.

| Method | HR (bpm) | abs. error vs GT (68 bpm) |
|---|---|---|
| Whole-clip single FFT (baseline) | 127.20 | 59.20 |
| Naive windowed (no continuity) | 102.24 | 34.24 |
| Task P — window-1-anchored continuity | 74.74 | 6.74 |
| **Task Q — quality-anchored continuity** | **126.29** | **58.29** |

**Verdict: the anchored version does NOT correct the known p21 case — it
is dramatically worse than Task P's window-1 anchor, and barely better
than the whole-clip baseline it replaces.** The reason is visible directly
in the table above: window 2's spectrum is *cleanly* dominated by a single
peak (its top-3 candidates are the most separated of any window, giving
it the highest quality score of the clip) — but that dominant peak is
itself the harmonic (126.29 bpm), not the true rate. A confidently wrong
window can score higher on this quality metric than a correct-but-noisier
window; window 1 (the naive anchor) happens to have its tallest peak land
much closer to the true rate (66.15 bpm) purely by chance, and Task P's
mechanism benefits from that. This is the same underlying problem in a
different guise: `windowedHeartRate.m`'s quality score measures spectral
*concentration*, not correctness, so it cannot by itself distinguish "a
clean read of the true pulse" from "a clean read of a harmonic."

### Action 3 — Full 107-subject v1 VIPL pool

Run via `scripts/run_task_q_anchored_windowed_batch.m`, reusing cached
`_rgb_traces.mat` / `_filtered_traces.mat` (no video reprocessing), same
pooled quality threshold derivation as Task P (0.2119, from the same 547
windows across the same 107 subjects — identical pooled distribution,
confirmed by matching min/median/max to Task P's report). All 107
subjects usable, 0 failures.

**Five-row comparison table (N=107, MAE/RMSE in bpm):**

| Method | N | MAE | RMSE | Pearson r |
|---|---|---|---|---|
| Whole-clip single FFT (current baseline) | 107 | 9.346 | 18.372 | 0.278 |
| Naive windowed (no gating, no continuity) | 107 | 10.338 | 15.643 | 0.316 |
| Gating only | 107 | 10.383 | 15.663 | 0.317 |
| Gating + continuity, window-1 anchor (Task P) | 107 | 12.466 | 21.575 | 0.237 |
| **Gating + continuity, quality anchor (Task Q)** | **107** | **10.621** | **19.421** | **0.205** |

**92 of 107 subjects (86%) have their highest-quality window somewhere
other than window 1** — so the anchor almost always moves. That movement
changed the final gated HR for **30 of 107 subjects** relative to Task
P's window-1-anchored result (same gating, same windows, both sides, so
this count is attributable to the anchor choice alone).

**Does anchoring at the highest-quality window close the gap Task P
found? Partially on MAE, no on RMSE and r — the honest reading is that
it narrows the regression without closing it, and the p21 case above
shows exactly why it can't fully close it.** MAE improves substantially
over Task P's window-1 anchor (12.47 → 10.62, a 1.85 bpm reduction) and
lands almost on top of the naive-windowed/gating-only baseline (10.34 /
10.38) — on MAE alone this looks like the fix nearly closes the gap.
RMSE tells a different story: it also improves over Task P's window-1
anchor (21.58 → 19.42) but remains **substantially worse** than the
gating-only baseline (15.66), a 3.76 bpm gap that MAE's improvement
masks — RMSE punishes large individual errors more than MAE does, and
p21-like cases (where the "best" window is a confident harmonic) produce
exactly the kind of large single-subject error that inflates RMSE without
moving MAE nearly as much. Pearson r actually gets **worse**, not better
(0.237 → 0.205, both well below gating-only's 0.317) — anchoring at a
different, generally-better window still doesn't fix the structural
problem that continuity propagates one window's choice into all the
others, and when that one window is a confidently-wrong harmonic (as on
p21), the anchor is now not window 1 but a plausible-looking decoy,
arguably harder to catch than an arbitrary first-window guess since it
looks locally trustworthy. **Bottom line: quality-anchoring is a real,
measurable improvement over window-1-anchoring on this specific pool
(better MAE and RMSE, 30/107 subjects changed), but it is not a fix for
Task P's underlying regression — a single-window's spectral quality score
is not a reliable proxy for "this window found the true rate, not a
harmonic of it," so anchoring on it inherits the same failure mode it was
meant to avoid, just less often.**

## Part 2 — Two-way forehead/cheek region switching

### Motivation

Task N found glabella and malar "bad everywhere" — worse than forehead
and cheek across all four scenarios by a wide margin, every time
([[segment6-task-n-multi-region-roi]]). This part drops both from the
candidate pool and asks whether a switcher built only from the two
regions that actually compete (forehead, cheek) does better than the
original 4-region switcher, which only won 2 of 4 scenarios.

### Action 4 — `computeRegionAgreement2Way.m` / `computeRegionSwitchingEstimate2Way.m`

`computeRegionAgreement2Way.m` mirrors `computeRegionAgreement.m`'s
`(max - min) / median` formula, specialized to exactly two candidates —
algebraically identical to `abs(HR_forehead - HR_cheek) / mean([...])`,
the same 2-way disagreement formula Task I/J already use for CHROM/POS.

`computeRegionSwitchingEstimate2Way.m` applies the SAME literal rule as
the 4-region switcher (argmin distance to the cross-region median,
forehead-over-cheek tie-break) restricted to two candidates. **This
surfaced a real, worth-reporting near-degenerate case, discovered while
implementing and testing the function, not designed in:** for exactly
two candidates `a` and `b`, `median([a,b]) == mean([a,b])`, and in exact
arithmetic both candidates sit *exactly* equidistant from that mean — the
argmin-to-median rule has no real information to discriminate between
them at all, only the tie-break. A first draft of the function's
docstring claimed IEEE-754 floating point preserves this exact tie
(reasoning that negating a value only flips its sign bit) and would
therefore select forehead on literally every subject — **that claim was
tested against real data and falsified**: cheek was selected on 15-20% of
subjects in every scenario, not 0%. The actual mechanism: computing the
shared mean requires an addition (`a + b`) that itself can round in
floating point before the exact halving step, and that single rounding
step is enough to nudge one candidate's distance a hair below the
other's. The corrected, verified understanding (now in the function's
docstring): this rule is a **near-coin-flip** between forehead and cheek
whenever the two roughly agree, decided mostly by sub-epsilon
floating-point rounding noise rather than any real per-subject signal —
it lands on forehead 80-85% of the time on this project's data simply
because the tie-break favors forehead whenever rounding noise doesn't
happen to tip the other way, not because it is meaningfully weighing
which region to trust.

### Action 5 — Task N's existing 4-scenario, 20-subject pool

Run via `scripts/run_task_q_2way_region_switching.m`, reusing
`results/metrics/segment6_task_n_region_hr_summary.csv` directly — no
reprocessing.

| Scenario | Method | N | MAE | RMSE | Pearson r |
|---|---|---|---|---|---|
| v1 (baseline) | 2-way switch (forehead/cheek) | 20 | 8.33 | 16.62 | 0.246 |
| v1 (baseline) | 4-region switch (Task N) | 20 | 8.00 | 16.56 | 0.621 |
| v1 (baseline) | **best single region (cheek)** | 20 | **5.27** | **7.91** | **0.852** |
| v2 (motion) | 2-way switch | 20 | 9.29 | 11.99 | 0.604 |
| v2 (motion) | **4-region switch (Task N)** | 20 | **7.72** | **10.68** | **0.662** |
| v2 (motion) | best single region (forehead) | 20 | 8.18 | 11.18 | 0.575 |
| v4 (bright) | 2-way switch | 20 | 3.99 | 6.49 | 0.849 |
| v4 (bright) | 4-region switch (Task N) | 20 | 3.52 | 4.79 | 0.897 |
| v4 (bright) | **best single region (forehead)** | 20 | **3.03** | **4.67** | **0.942** |
| v5 (dark) | 2-way switch | 20 | 5.49 | 9.97 | 0.641 |
| v5 (dark) | **4-region switch (Task N)** | 20 | **4.79** | **6.92** | **0.791** |
| v5 (dark) | best single region (cheek) | 20 | 4.98 | 8.08 | 0.697 |

Selection counts (of 20 subjects, forehead / cheek): v1 = 16/4, v2 = 16/4,
v4 = 17/3, v5 = 17/3 — consistent with the near-coin-flip behavior
documented above, not a scenario-dependent pattern.

**Does dropping the two weak regions let switching beat the best single
region more consistently? No — it beats it in ZERO of 4 scenarios, worse
than the original 4-region switch's 2-of-4 record.** The 2-way switch
loses to the best single region in every scenario (v1: 8.33 vs cheek's
5.27; v2: 9.29 vs forehead's 8.18; v4: 3.99 vs forehead's 3.03; v5: 5.49
vs cheek's 4.98), and also loses to the original 4-region switch in every
scenario. This is the direct, predictable consequence of Action 4's
finding: with only two near-equidistant candidates, the switching rule
has essentially no real signal to act on and ends up substituting cheek
for forehead (or vice versa) on ~15-20% of subjects for reasons close to
floating-point noise rather than genuine disagreement, and roughly 1 in 5
of those substitutions actively hurts rather than helps since it isn't
targeting the subjects that actually need it. The 4-region switcher, by
contrast, draws on four genuinely different candidates (even though two
of them, glabella and malar, are individually weak) — enough real spread
across four numbers for the median to carry actual information, which
the 2-candidate case structurally cannot provide. **Bottom line: dropping
weak regions from the candidate pool does not help here, because the
weak regions were never what made the 4-region switcher work — the
switcher's real signal came from having enough candidates for
"distance to median" to mean something, and collapsing to exactly two
candidates removes that signal rather than concentrating it.**

## Outputs

- `matlab/src/validation/selectHarmonicConsistentHR_anchored.m` — Part 1 Action 1.
- `matlab/scripts/run_task_q_p21_anchored_check.m` — Part 1 Action 2 isolated p21 check.
- `matlab/scripts/run_task_q_anchored_windowed_batch.m` — Part 1 Action 3 full-pool batch.
- `results/metrics/segment6_task_q_anchored_windowed_hr_summary.csv` — per-subject, all five HR methods + ground truth + anchor window index + changed-by-anchoring flag.
- `results/metrics/segment6_task_q_anchored_windowed_metrics.csv` — pooled MAE/RMSE/Pearson r per method (five rows).
- `matlab/src/validation/computeRegionAgreement2Way.m` — Part 2 Action 4 (2-way agreement metric).
- `matlab/src/validation/computeRegionSwitchingEstimate2Way.m` — Part 2 Action 4 (2-way switching estimator).
- `matlab/scripts/run_task_q_2way_region_switching.m` — Part 2 Action 5.
- `results/metrics/segment6_task_q_2way_switching_summary.csv` — per-scenario MAE/RMSE/Pearson r for 2-way switch, best single region, forehead alone, cheek alone.

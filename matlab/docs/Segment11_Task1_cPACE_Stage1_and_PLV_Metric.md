# Segment 11 Task 1 — cPACE Stage 1 and the Cross-ROI PLV Metric

Run 2026-09-13. The two highest-value, best-supported next steps identified
by `docs/Segment10_Task3_Tier0_Diagnostics.md`'s verdict: (1) implement and
evaluate Kaur, Lakshminarayanan & Saini's cPACE Stage 1 projector as a new,
gated, off-by-default pre-step ahead of CHROM/POS, and (2) promote the
cross-ROI PLV computation from a Task 3 one-off into a standing, reusable
validation function. No other Tier 1/2/3 item from
`docs/Segment10_Task2_Solution_Literature_Search.md` §8 was started.

**Headline result, stated up front because it changes the shape of
everything below**: cPACE Stage 1, wired exactly as specified and evaluated
on Spandan's own combiners, is **a provable, exact algebraic no-op for
POS** and **a real but modest regression for CHROM** on this project's own
100-subject pool. Neither combiner moves in the direction Kaur et al.'s own
cPACE-vs-POS comparison would suggest. This is a genuine negative result,
not an ambiguous one rounded down — see §1 for the proof, verified
computationally to floating-point precision, not just derived on paper.

New files: `matlab/src/pulseextraction/cpaceProjection.m`,
`matlab/src/validation/computeCrossROIPLV.m`,
`matlab/scripts/run_segment11_task1_cpace_and_plv.m`. Do-not-touch files
(`chromCombine.m`, `posCombine.m`, `fftHeartRate.m`,
`adaptiveHarmonicFilter.m`, `bandpassMorphology.m`, `waveletDenoise.m`,
`bandpassClean.m`, `extractROISignals.m`) are called, never modified —
confirmed via `git status` before writing this doc.

---

## Method

### cPACE Stage 1 (`cpaceProjection.m`)

Per Kaur et al. (Biomed. Opt. Express 17(7):3832, 2026), the isochromatic
cardiac component lies along the skin's mean reflectance direction and
cannot be separated from the chromatic component by any temporal filter —
only a spatial (cross-channel) projection removes it:

```
q_hat = [Rbar, Gbar, Bbar] / norm([Rbar, Gbar, Bbar])   (raw per-channel temporal means)
P     = I - q_hat * q_hat'
x_corrected(t) = P * x(t)                                (applied per raw sample)
```

`q_hat` is built from exactly the same raw per-channel temporal means
(`mean(R)`, `mean(G)`, `mean(B)`) that `chromCombine.m`/`posCombine.m`
already compute for their own normalization step and `ratioOfRatios.m`
already computes for its DC term — not a separately-invented convention.

**Wiring (the part that turns out to matter — see §1):** the projected
trace `Rc,Gc,Bc` replaces `R,G,B` as the input to `detrendSignal.m` →
`bandpassClean.m`, exactly like the unmodified pipeline. But
`chromCombine.m`/`posCombine.m`'s own `RRaw`/`GRaw`/`BRaw` normalization
argument is **always the original, unprojected raw trace**, in both the ON
and OFF condition. This is not a design choice made for convenience — it is
a **necessity**: `cpaceProjection.m` removes the raw trace's mean *exactly*
(`mean(Rc) = mean(Gc) = mean(Bc) = 0` to numerical precision, since `q_hat`
is defined as that mean's own normalized direction), so normalizing by the
projected trace's own mean would divide by zero. `cpaceProjection.m`'s own
header states this explicitly for future callers.

A boolean condition (`'off'`/`'on'`) is threaded through
`run_segment11_task1_cpace_and_plv.m`; `'off'` reproduces the existing
pipeline byte-for-byte (confirmed: `'off'` numbers below match Task 1/the
production pipeline's own pooled HR numbers). **No default changed — cPACE
stays an opt-in pre-step, never called by any existing script.**

`cpaceProjection.m` also returns `skinColorAngleDeg`, the angle between
`q_hat` and the skin-tone axis `[1,1,1]/sqrt(3)` — Kaur et al.'s own
"skin-colour angle θ" — for free, since it falls out of the same `q_hat`
computation the Stage 1 projection already needs.

### Evaluation pool

- **HR accuracy + waveform correlation**: the same 100-subject pool
  Segment 10 Task 1 established (5 UBFC-D1 + 95 VIPL v1/source1), read
  directly from `results/metrics/segment10_waveform_fidelity_per_subject.csv`
  (the exact ID list, not re-derived from Segment 7 Task K's raw
  prototypes/correlation-matrix cache — Task 1's own script never used that
  cache for its actual computation either, only to establish which
  subjects have a real GT waveform; this script follows the same
  precedent). No video reprocessed — everything rebuilt from
  `data/processed/*_rgb_traces.mat`.
- **Cross-ROI PLV cross-check**: the same 20 VIPL v1/source1 subjects
  Segment 10 Task 3 Action 2 used (`p1, p3, p4, p6–p22`) — the only
  subjects with all four Segment 6 Task N regions
  (forehead/glabella/malar/cheek) cached. A smaller subset of the 100
  above, stated explicitly.
- HR predicted via `fftHeartRate.m` on the final (post-second-bandpass)
  pulse signal; ground-truth HR = `mean(gt.hr)`, the same convention
  `scripts/run_vipl_integration_batch.m` already uses pooled-wide. Pooled
  via `validation/computeMetrics.m` (this project's own standard MAE/RMSE/
  Pearson-r aggregator).
- Waveform correlation: `morphology/estimateLagPolarityByGroundTruth.m`
  (Task 1's own lag/polarity alignment) → z-score both aligned signals →
  Pearson r — the exact same method and metric Task 1 reported as its
  headline number.

### `computeCrossROIPLV.m`

Extracted, not rewritten, from Task 3 Action 2's inline computation. Takes
a cell array of already-extracted pulse signals (one per ROI region, same
length/fs) and returns the mean PLV across every region pair plus a
per-pair breakdown table — generic to whatever pulse-extraction method the
caller used, not hardcoded to CHROM/POS/cPACE. A usage note was added to
`README.md`'s folder-structure listing ("use this when no ground truth is
available") so a future session without this task's context still finds
it.

For this task, each region's raw trace was independently run through the
same detrend→bandpass→combine sequence (with or without its own
`cpaceProjection.m` call, per condition) to produce the per-region pulse
signal `computeCrossROIPLV.m` consumes. **Each region gets its own
`q_hat`** — the skin's mean reflectance direction is a per-ROI-patch
quantity (different average lighting/geometry per patch), not necessarily
identical across one face's four regions.

---

## 1. Result: with vs. without cPACE Stage 1 (the table, front and center)

| Metric | Branch | cPACE OFF | cPACE ON | n |
|---|---|---|---|---|
| HR MAE (bpm) | CHROM | 7.86 | **8.72** | 100 |
| HR RMSE (bpm) | CHROM | 16.74 | **19.05** | 100 |
| HR Pearson r (pooled) | CHROM | 0.365 | **0.275** | 100 |
| Waveform corr, median | CHROM | 0.445 | **0.417** | 100 |
| Waveform corr, IQR | CHROM | 0.317–0.585 | 0.318–0.531 | 100 |
| Cross-ROI PLV, mean | CHROM | 0.254 | 0.241 | 20 |
| HR MAE (bpm) | POS | 7.87 | **7.87** | 100 |
| HR RMSE (bpm) | POS | 16.35 | **16.35** | 100 |
| HR Pearson r (pooled) | POS | 0.311 | **0.311** | 100 |
| Waveform corr, median | POS | 0.452 | **0.452** | 100 |
| Waveform corr, IQR | POS | 0.353–0.608 | 0.353–0.608 | 100 |
| Cross-ROI PLV, mean | POS | 0.271 | 0.271 | 20 |

Full per-subject and summary tables:
`results/metrics/segment11_cpace_before_after.csv`. Figures:
`results/figures/segment11_hr_scatter.png`,
`results/figures/segment11_waveform_corr_before_after.png`,
`results/figures/segment11_plv_before_after.png`.

**POS's numbers are not merely similar — they are identical to the limits
of floating-point arithmetic**, checked per-subject, not just at the pooled
level: across all 100 subjects, the maximum per-subject HR difference
between ON and OFF is exactly **0**, and the maximum per-subject waveform-
correlation difference is **1.5×10⁻¹⁴** (floating-point noise). One
subject's raw combined POS signal was checked sample-by-sample: max
absolute difference **5.2×10⁻¹⁶**. This is not a coincidence of this
dataset — §2 proves it algebraically, for any subject, any skin tone.

**CHROM's numbers are genuinely, if modestly, worse with cPACE Stage 1
on.** 74 of 100 subjects show a *lower* waveform correlation with cPACE on
(26 improve); the mean per-subject change is -0.022, median -0.019 (range
-0.148 to +0.175 — not uniform, but net negative). On HR, most subjects'
FFT-peak-picked bpm value doesn't move at all (HR estimation is a discrete
peak-selection process, insensitive to small continuous perturbations
below the threshold that flips the winning frequency bin) — only 23 of 100
subjects show any HR change larger than 0.01bpm (17 worse, 6 better) — but
where it does move, it can move a lot: **7 of 100 subjects regress by more
than 10bpm**, the worst being `VIPL_p96` (28.1bpm error → 98.3bpm error,
a harmonic-lock-like flip to the wrong FFT peak).

---

## 2. Why POS is exactly invariant (proof, then verification)

**Claim: for any subject, any skin tone, `cpaceProjection.m` applied ahead
of `posCombine.m` (with normalization always by the original raw means, as
wired above) produces a bit-identical POS output.**

**Proof.** For any fixed linear combination `w'x` of a 3-channel raw
sample `x = [R;G;B]`, projecting first gives `w' * P * x = w'x -
(w'*q_hat)*(q_hat'*x)` (since `P = I - q_hat*q_hat'` is symmetric). If
`w` is already orthogonal to `q_hat` (`w'*q_hat = 0`), the projection
changes nothing: `w'*x_corrected = w'*x`, exactly.

`posCombine.m`'s own two projections (lines 39-40), written as raw-sample
linear combinations with each channel weighted by its own reciprocal mean:

```
S1 = Gn - Bn        = [0,       1/Gbar,  -1/Bbar ] . [R;G;B]
S2 = Gn + Bn - 2*Rn = [-2/Rbar, 1/Gbar,   1/Bbar  ] . [R;G;B]
```

Dotting each weight vector with the (unnormalized) mean vector
`[Rbar,Gbar,Bbar]`:

```
w_S1 . [Rbar,Gbar,Bbar] = 0*Rbar + (1/Gbar)*Gbar + (-1/Bbar)*Bbar = 0 + 1 - 1 = 0
w_S2 . [Rbar,Gbar,Bbar] = (-2/Rbar)*Rbar + (1/Gbar)*Gbar + (1/Bbar)*Bbar = -2 + 1 + 1 = 0
```

**Both are exactly zero, for any nonzero Rbar/Gbar/Bbar** — this is an
algebraic identity of POS's own coefficient pattern (`[0,1,-1]` and
`[-2,1,1]`, both summing to zero) combined with per-channel-own-mean
normalization, not a property of any particular subject's data. Since
`q_hat` is just `[Rbar,Gbar,Bbar]` normalized to unit length, `w_S1 . q_hat
= w_S2 . q_hat = 0` follows immediately, and both are unaffected by the
projection. `S1` and `S2` feed into POS's std-ratio blend and everything
downstream (HR, waveform correlation, PLV) — all inherit the same exact
invariance.

Filtering does not break this: `detrendSignal.m` + `bandpassClean.m` are
linear, time-invariant, per-channel-independent operators, so they commute
with `P`'s fixed cross-channel mixing — filtering the projected trace gives
exactly `P` applied to the filtered trace, which is what the proof above
assumes.

**Verified computationally**, not just derived: `qHat` computed for
`VIPL_p1_v1_source1` is `[0.6945, 0.5527, 0.4606]`; the projected trace's
own mean is `~1e-13` (zero to numerical precision, confirming the
zero-mean claim); the resulting POS signal differs from the unprojected
POS signal by a max absolute `5.2e-16` (machine epsilon); across the full
100-subject pool, POS's per-subject HR estimate differs by exactly **0**
in every case.

**CHROM's own basis vectors do not have this property.** `chromCombine.m`'s
`Xs = 3*Rn - 2*Gn` and `Ys = 1.5*Rn + Gn - 1.5*Bn` have raw-coefficient
sums of **1** and **1** respectively (`3-2+0=1`, `1.5+1-1.5=1`), not zero —
so `w_Xs . q_hat` and `w_Ys . q_hat` are generally nonzero, and cPACE
genuinely changes CHROM's output. This exactly matches
`docs/Segment10_Task2_Solution_Literature_Search.md` §0's own citation of
Kaur et al.: *"POS's basis vectors are orthogonal to [1,1,1] by
construction... CHROM's are not, so its leakage is 0.58 even at skin-colour
angle 0°."* What this task adds is the **stronger, exact version specific
to Spandan's own implementation**: because `posCombine.m` normalizes each
subject by their own measured channel means (not a fixed reference white
point), POS here is orthogonal not just to the generic `[1,1,1]` axis in
theory, but to *that specific subject's own* `q_hat` in practice, to
machine precision. That is a stronger and more useful property than the
paper's own generic framing describes for a textbook POS derivation — and
it is precisely why Stage 1, applied exactly as specified, cannot help POS
here no matter what future subject or cohort is measured on.

---

## 3. Direction check against Kaur et al.'s own reported numbers

Kaur et al.'s cPACE (their full 3-stage pipeline) vs. POS HR MAE across
four cohorts: **1.7/3.7/1.7/1.1** vs. **2.8/9.5/16.8/17.8 BPM** — cPACE
wins by a wide, sometimes enormous margin.

**Spandan's numbers do not move in the same direction, for either
combiner — stated plainly, not rounded up:**

- **POS: by definition, cannot move at all** (§2's proof). This is not "no
  support" in the sense of a null experimental result — it is a structural
  non-applicability: Kaur et al.'s comparison is cPACE's *entire 3-stage
  pipeline* against a *generic* POS derivation, not "POS + their Stage 1
  alone" against Spandan's own per-subject-adaptive POS implementation
  specifically. Testing Stage 1 in isolation ahead of an already-θ-adaptive
  POS was never going to reproduce their full-pipeline gap, and now there
  is a verified mechanistic reason why, rather than an unexplained
  mismatch.
- **CHROM: moves backward.** MAE rises from 7.86 to 8.72bpm (+11%), pooled
  HR-level Pearson r falls from 0.365 to 0.275, median waveform correlation
  falls from 0.445 to 0.417. This is the opposite direction from what
  Stage 1 is supposed to do, on this project's own pool, with Stage 1
  wired exactly as specified.

**This does not retract Task 3 Action 4's finding** (Spandan's own
measured POS cardiac angle, 109.5° median, far from the assumed 57° and
matching Kaur et al.'s own reported 96.6–115.5° range) — that measurement
is about the direction of cardiac-band *variance* within POS's own output
plane (already orthogonal to `q_hat`, per §2), a different question from
"how much energy lies along `q_hat` itself," which is what Stage 1
targets. The isochromatic-contamination mechanism may well still be real
and present in Spandan's data; this task's result is specifically about
whether *removing the q_hat direction ahead of POS/CHROM's own existing
algebraic forms* helps — and for the wiring specified in this task's
brief, it provably cannot help POS and empirically does not help CHROM.

---

## 4. Skin-colour angle (Action 1's other explicit ask)

| Group | n | min | median | mean | max |
|---|---|---|---|---|---|
| all (UBFC-D1 + VIPL v1/source1) | 100 | 0.06° | 8.61° | 7.99° | 15.38° |

Full per-subject table:
`results/metrics/segment11_cpace_skin_angle_per_subject.csv`. Figure:
`results/figures/segment11_skin_angle_hist.png`.

**Every one of the 100 subjects falls inside Kaur et al.'s own reported
"lightly pigmented" range (~5–10°)** — none anywhere close to their
"darkly pigmented" range (~30–50°), where the paper's own reported gains
are largest. This confirms, directly on Spandan's own data rather than by
inference, that UBFC and VIPL are not stand-ins for the skin-tone regime
that matters most for this project's planned Bangladeshi self-collected
set (pipeline stage 7): if that set's subjects sit at a materially higher
θ, as predicted, the isochromatic contamination magnitude there could be
substantially larger than anything measurable on the two cohorts available
today. **Two different generalization stories apply to the two findings
above**: POS's exact invariance (§2) is a pure algebraic fact that holds
for *any* θ, so it will hold on a future dark-skin cohort too, with
certainty. CHROM's empirical regression (§1) was measured on a
low-θ cohort only and is not guaranteed to generalize to a high-θ cohort
— it could plausibly reverse sign where the contamination is actually
large enough to matter, a real open question this task does not resolve
and should not be assumed either way.

---

## 5. Honest caveats

- This tests cPACE **Stage 1 only**, ahead of Spandan's **existing**
  CHROM/POS, not Kaur et al.'s own full 3-stage cPACE combiner (their
  Stage 2 phase-optimal eigenvector selection and Stage 3 in-band noise
  suppression are out of scope, per this task's own brief). The negative/
  null result here says nothing about whether their full pipeline would
  do better as a wholesale replacement.
- The HR-level pooled Pearson r (across 100 subjects, bpm vs. bpm) and the
  per-subject waveform correlation r (within one subject's aligned
  waveform vs. its own GT) are two different kinds of correlation reported
  side by side in the table above — kept clearly labeled rather than
  conflated, same distinction Task 1 and Task 3 both maintained.
- The cross-ROI PLV cross-check (n=20) is a smaller subset of the 100-
  subject pool, bounded by which subjects have all four Task N regions
  cached — stated explicitly, not silently generalized to the full 100.
- CHROM's per-subject regression is not uniform (26/100 subjects actually
  improve, up to +0.175) — reported as a net-negative pool effect, not a
  claim that cPACE Stage 1 hurts every single subject.
- `VIPL_p96`'s 28→98bpm HR regression is a single dramatic outlier driving
  a meaningful share of CHROM's pooled MAE/RMSE increase — flagged rather
  than smoothed over, the same way this project flagged `p85`'s wavelet-
  ablation regression and `p21`'s harmonic-confusion anecdote previously.

---

## 6. Recommendation: should cPACE move from optional flag to default-on?

**No, for either combiner, on the evidence gathered here.**

- **POS**: enabling the flag changes nothing (§2, proven and verified to
  machine precision) — there is no benefit, only wasted computation and a
  false impression that something was fixed. Not worth defaulting on.
- **CHROM**: enabling the flag makes results modestly worse on this
  project's own 100-subject pool (net waveform-correlation and HR
  regression, one severe single-subject flip). Defaulting it on would be a
  regression against the do-not-touch pipeline's current behavior, exactly
  what the off-by-default design in `cpaceProjection.m`/this script was
  built to prevent.

**The flag stays available, off by default, exactly as specified in the
brief** — useful for future experimentation (e.g. once a higher-θ cohort
exists to test CHROM's regression against), but not adopted.

**What this result redirects attention to, for whichever future session
picks up cPACE again:** Stage 1 alone, wired this way, is not the lever.
Candidates worth considering before trying Stage 1 again in a different
form: (a) Kaur et al.'s own Stages 2-3 (not attempted here, genuinely
untested); (b) a time-varying/windowed `q_hat` instead of one whole-clip
constant, which could interact differently with detrend/bandpass's own
time-invariance assumption; (c) testing this exact Stage-1 wiring on a
real higher-θ (darker-skinned) cohort once one exists, since §4 shows this
task could only test the regime where the paper's own predicted gains are
smallest. None of these are started here — flagged as open questions for a
future decision, not results.

**Cross-ROI PLV, separately, is adopted as a standing tool** (§0 of Task
3's own verdict already recommended this) — `computeCrossROIPLV.m` is now
a permanent, reusable, ground-truth-free validation function, documented in
`README.md`, ready for any future subject with Task N's cached regions but
no contact-PPG ground truth.

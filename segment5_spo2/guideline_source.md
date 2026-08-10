---
title: "Segment 5 — SpO2 Ratio-of-Ratios \\& Empirical Calibration"
subtitle: "Spandan: Contactless Vital Sign Monitoring — EEE 312 DSP Project, BUET"
author: "Team Spandan"
date: "\\today"
geometry: margin=2.5cm
fontsize: 11pt
colorlinks: true
---

# Why This Segment Exists

Segments 2-4 got us a clean pulse signal and a heart rate. This segment
tackles a genuinely different measurement: **SpO2**, the percentage of
hemoglobin in arterial blood that is carrying oxygen. Unlike heart rate
(a *frequency*, read straight off an FFT peak), SpO2 is a *physiological
ratio* that has no direct optical measurement — it has to be inferred
from how differently oxygenated vs. deoxygenated blood absorbs two
different wavelengths of light, and that inference has to be calibrated
empirically against real ground-truth SpO2 readings, not derived from
first principles alone.

::: intuition
**Intuition first.** A thermometer measures temperature directly — the
mercury (or the thermistor) responds physically to heat, no fitting
required. A pulse oximeter is not like that. It measures how much red and
infrared light a fingertip (or, here, a patch of facial skin) absorbs as
blood pulses through it, and then relies on a curve — fitted in advance,
against real patients with real measured SpO2 — to convert that optical
ratio into a percentage. Every commercial pulse oximeter on the market
has this same empirical calibration curve baked into it at the factory.
This segment builds the same kind of curve, from scratch, using this
project's own (much smaller) dataset.
:::

# Why AC/DC Per Channel Physically Encodes Oxygenation Information

Every heartbeat pushes a fresh pulse of arterial blood into the tissue
being observed (a fingertip in classic pulse oximetry, a forehead/cheek
patch in this project's facial video). That blood pulse is genuinely
extra volume, briefly, in the optical path — the tissue is very slightly
"redder" or "less red" at the peak of each pulse than in between beats.
Any single color channel's brightness over time can be split into two
parts:

- **DC (the mean level)**: the steady, unchanging brightness contributed
  by everything that ISN'T the beat-to-beat blood volume change — skin,
  bone, venous blood, ambient lighting, camera sensor characteristics.
  This is the *overwhelming majority* of the signal's total brightness.
- **AC (the pulsatile ripple)**: the small amount by which brightness
  wiggles up and down, in sync with the heartbeat, on top of that DC
  level. This is a tiny fraction of the total signal (often well under
  1%) but it's the part that's actually changing *because of* the blood
  pulse.

`AC / DC` — the pulsatile ripple expressed as a *fraction* of the
channel's own average brightness — is what pulse oximetry actually
measures per channel, specifically because it cancels out how bright or
dim that particular channel happened to be for reasons that have nothing
to do with blood (skin tone, lighting, camera gain). Two channels
(traditionally Red and Infrared) each get their own `AC/DC`, and the
**ratio of those two ratios** is the final quantity, `R`, that gets
mapped to SpO2:

```
R = (AC_Red / DC_Red) / (AC_Blue / DC_Blue)
```

::: pausecheck
**Pause and check yourself.** Why divide by `DC` at all — why not just
compare `AC_Red` to `AC_Blue` directly? (Hint: think about what would
happen to a raw, un-normalized `AC_Red` value if the exact same subject
were filmed in a much brighter room, with nothing about their actual
blood oxygenation having changed.)
:::

# Why Blue Substitutes for Infrared

Classic pulse oximetry uses Red (~660 nm) and Infrared (~940 nm) light,
specifically because oxygenated and deoxygenated hemoglobin absorb those
two wavelengths very differently — that difference is *why* the
ratio-of-ratios tracks oxygenation at all. An ordinary phone or webcam
camera sensor has no infrared channel. This project (like a body of prior
published remote-photoplethysmography research) substitutes the camera's
**Blue** channel for Infrared. This is worth being precise about: it is a
**known, published approximation used in the rPPG literature** — not
something invented for this project, and not a claim that Blue light and
Infrared light interact with hemoglobin identically. It's a practical
substitution that published work has shown correlates usefully with true
SpO2, with the explicit understanding that any calibration built on top
of it has to be fit empirically against real ground truth (see the next
section) rather than trusted from first-principles optics alone —
precisely because Blue is a stand-in, not the real thing.

::: pitfall
**Common beginner mistake.** Treating "Blue substitutes for Infrared" as
if it means Blue light physically behaves like Infrared light in
hemoglobin. It doesn't — the absorption physics is genuinely different.
What's being claimed is much narrower: that the *pattern* of Blue's
pulsatile response correlates usefully enough with true oxygenation,
once empirically calibrated, to be worth using in a camera-only system
that has no real IR sensor available. That's an empirical claim, tested
by calibration and validation, not a physics identity.
:::

# Why the R-to-SpO2 Relationship Must Be Fit Empirically

Even with real Red/Infrared hardware, the exact numerical relationship
between `R` and true SpO2 is not something you derive from the
Beer-Lambert absorption law and a calculator. It depends on details that
are extremely hard to model exactly from physics alone: the precise
spectral response curve of *this specific* camera sensor, the exact
center wavelength and bandwidth of *this specific* Blue channel, skin
thickness and scattering properties, sensor gain and exposure behavior,
and more. Every real-world pulse oximeter manufacturer handles this by
**empirical calibration**: recording `R` alongside a trusted reference
SpO2 measurement (often a blood-gas analyzer) across many subjects and
conditions, then fitting a curve (`spo2/calibrateSpO2.m` fits the simplest
possible version of this: a straight line, `SpO2 = A - B*R`) through the
observed data.

::: intuition
**Intuition first.** This is exactly like calibrating a home bathroom
scale. The scale doesn't derive your weight from the physics of its
springs and Hooke's Law computed from scratch — the manufacturer
calibrates it at the factory against known, trusted reference weights,
and every unit afterward just applies that fitted relationship. If you
skipped calibration and trusted a theoretical spring-physics formula
instead, small real-world imperfections (spring wear, temperature,
manufacturing tolerance) would throw the reading off in ways no amount of
better physics-from-first-principles would catch — only checking against
known-correct references does.
:::

# The Leakage Risk — and Why DATASET_1's 5 Subjects Make It Acute Here

**Calibration leakage** happens when a subject's own data is used both to
*fit* a calibration curve and to *evaluate* how well that curve predicts
that same subject. This inflates apparent accuracy in a way that has
nothing to do with how the method will perform on a genuinely new,
unseen subject — it's measuring "can this line reproduce a point it was
literally drawn through," not "can this line predict an unknown point."

::: pitfall
**Common beginner mistake.** Fitting `calibrateSpO2.m` on all 5 DATASET_1
subjects at once, then checking how close its predictions are to those
same 5 subjects' true SpO2, and reporting that closeness as the method's
accuracy. A straight line fit through 5 points and then evaluated on
those same 5 points will always look deceptively good — it's optimized
to be close to exactly those points. This tells you nothing about
subject 6, who the line has never seen.
:::

This project's leave-one-out loop (`run_segment5_dataset1_calibration_
batch.m`) exists specifically to avoid this: each of the 5 subjects is
predicted using a calibration fit only on the *other* 4, rotating through
all 5, so no subject ever contributes to its own prediction.

**Why this is a bigger concern here than it would be with more data:**
DATASET_1 has exactly 5 subjects with facial-video SpO2 ground truth.
Leave-one-out with only 5 subjects means every single fold's calibration
is fit on just 4 points — barely more than the 2 points mathematically
required to define a line at all. It also means the *whole dataset's* own
SpO2 range is narrow (this project's 5 subjects span roughly 96-99%,
confirmed in the Line-by-Line document's results table), so even a
perfectly leakage-free fit is working with very little real variation to
learn from. Leave-one-out here is a genuine, correct leakage-avoidance
measure — but it does not, and cannot, turn 5 thin data points into a
trustworthy calibration. Both things are true at once: the *methodology*
(leave-one-out) is sound; the *data volume* it's applied to is not enough
to draw strong conclusions from, and this document is explicit about
that rather than letting a clean-sounding cross-validation procedure
imply more confidence than 5 subjects can actually support.

::: pausecheck
**Pause and check yourself.** Suppose DATASET_1 had 50 subjects instead
of 5, still spanning a similarly narrow 96-99% true SpO2 range. Would
leave-one-out cross-validation across those 50 subjects fully solve the
"thin data" concern raised above, or would a real limitation remain? What
specifically would still be missing?
:::

# What the Hoffman Sanity Check Does and Does NOT Prove

DATASET_1's narrow SpO2 range (96-99%) can confirm the *code* runs and
produces plausible numbers, but it genuinely cannot test whether
`ratioOfRatios.m`/`calibrateSpO2.m` respond correctly across a *wide*
range of true oxygenation, because DATASET_1 simply doesn't contain much
range to test against. The Hoffman et al. finger-camera oximetry dataset
(github.com/ubicomplab/oximetry-phone-cam-data) was used as a
**different, deliberately wide-range** dataset purely to fill that gap.

**What it is:** subjects with a finger from each hand pressed directly on
a smartphone camera lens with the flash on, recorded while a controlled
Varied FiO2 protocol (a clinically supervised mixture of oxygen and
nitrogen) deliberately lowered their SpO2 over roughly 12-16 minutes, down
to as low as the mid-60s%, then let it recover. Six subjects, confirmed
directly by opening the dataset's own CSV files (not assumed from its
README) — see `docs/HOFFMAN_DATA_FORMAT.md` for the full inspection
notes.

**What a good result here proves:** that this segment's actual production
code (`ratioOfRatios.m` and `calibrateSpO2.m`, called directly, not
reimplemented) responds sensibly — in the physiologically correct
direction, with a real, checkable relationship — when given real optical
data spanning a genuinely wide oxygenation range. That's a **code-
correctness** claim.

**What it does NOT prove:** anything about facial-video SpO2 accuracy.
Finger-on-camera-with-flash is a completely different optical
regime from facial rPPG — direct contact instead of distance, an active
flash instead of ambient/room lighting, and a very different tissue
thickness and blood volume behind the measurement. A good result on
Hoffman data is evidence the *code* is sound; it is not evidence that
the *facial pipeline* will hit similar numbers. Only DATASET_1 (and,
later, VIPL-HR/PURE once access arrives) can speak to actual facial-video
SpO2 accuracy.

::: intuition
**Intuition first.** Think of this the way you'd think about unit-testing
a sorting algorithm on a big, deliberately varied list of random numbers
before trusting it on your real, much smaller, oddly-distributed dataset.
Confirming the algorithm correctly sorts a wide, varied test case tells
you the *logic* works. It doesn't tell you anything about whether your
real dataset's particular quirks (near-duplicate values, a narrow range,
whatever they may be) will behave the same way — that still has to be
checked on the real data directly.
:::

The actual results obtained (per-subject correlations, the pooled-vs-
per-subject discrepancy that was investigated rather than accepted at
face value, and the final test-set error) are reported in full, with the
real numbers, in `Segment5_LineByLine_Explanation.md` Part 4-5 — this
document covers the theory; that one covers what was actually measured.

# Common Pitfalls in This Segment

**Confusing AC/DC granularity with formula correctness.** The
ratio-of-ratios *formula* is identical whether it's computed once per
whole clip (DATASET_1) or once per short window (Hoffman). What changes
is how much of the underlying recording each `mean()`/`std()` call sees.
Getting the formula right and getting the granularity right are two
separate judgment calls — this segment documents both, in
`Segment5_LineByLine_Explanation.md` Part 0, because it's easy to assume
"one function, one correct way to call it" when the right window length
actually depends on whether the physical quantity you're measuring is
expected to change within a single recording.

**Trusting a pooled multi-subject fit's correlation number without
checking per-subject structure underneath it.** As detailed in the
Line-by-Line document, a pooled correlation across several subjects can
look much weaker than any individual subject's own correlation, purely
because of between-subject baseline offsets — not because there's no real
relationship. Always check whether an unexpectedly weak aggregate number
is hiding real per-subject signal before concluding "no relationship" or
"bug."

**Treating a wide-range sanity check as a facial-video validation
result.** Covered at length above — worth repeating here because it's the
single easiest thing for a reader skimming results tables to get wrong.

# How This Segment's Outputs Feed Into Segment 6

Both this segment's batch scripts save CSVs into `results/metrics/` —
`segment5_dataset1_calibration.csv` (5 leave-one-out rows) and
`segment5_hoffman_sanity_check.csv` (one row per held-out test window).
Neither is Segment 6's job. `validation/runLOSO.m`,
`validation/computeMetrics.m`, and `validation/blandAltman.m` (all still
untouched stubs, explicitly out of scope for this segment) are where the
actual, statistically meaningful leave-one-subject-out validation
happens — computing MAE, RMSE, Pearson correlation, and Bland-Altman
agreement across every subject with usable ground truth, for both HR
(DATASET_1 + DATASET_2) and SpO2 (DATASET_1 only, since it's the only
source of SpO2 ground truth this project currently has). This segment's
job was narrower and more foundational: get `ratioOfRatios.m` and
`calibrateSpO2.m` correctly implemented, demonstrate they work on real
data with a real leakage-avoidance strategy, and be explicit about
exactly how much (or little) the thin DATASET_1 sample can actually
prove. Segment 6 is where the team finds out, with proper statistics and
across the full available data, whether the method itself holds up.

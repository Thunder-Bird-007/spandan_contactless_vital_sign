---
title: "Segment 6 — Formal Validation: LOSO, Metrics \\& Bland-Altman"
subtitle: "Spandan: Contactless Vital Sign Monitoring — EEE 312 DSP Project, BUET"
author: "Team Spandan"
date: "\\today"
geometry: margin=2.5cm
fontsize: 11pt
colorlinks: true
---

# Why This Segment Exists

Segments 2-5 built the whole measurement chain: face detection, signal
filtering, heart rate extraction, and an SpO2 calibration attempt. Every
one of those segments produced a real number for a real subject and
compared it, informally, against that subject's own ground truth. What none
of them did — deliberately, by design — was ask the harder, more honest
question: **across every subject available, taken together, how good is
this method really, and how do we know?** That is Segment 6's entire job.
It touches no video, no filter, no FFT — it consumes the numbers Segments
4-5 already produced and puts them through the same statistical machinery a
real clinical device validation study would use.

::: intuition
**Intuition first.** Segments 2-5 were like a student solving practice
problems one at a time and checking each answer against the back of the
book. Segment 6 is the final exam: pool every problem attempted so far,
grade all of them together, and report a real, defensible score — not "I
got this one right," but "here is my accuracy, my error spread, and my
correlation with the answer key, computed honestly, with no problem's
answer key ever leaking into how that same problem was solved."
:::

# What Bland-Altman Actually Shows, Versus a Simple Scatter

A plain scatter plot of predicted vs. true values answers one question:
*do these two move together?* Pearson correlation is the number version of
that same question. Both can be fooled by a **constant bias** — two methods
that always disagree by the same fixed amount will still correlate close to
perfectly, because "moving together" says nothing about "being equal."

A Bland-Altman plot asks a different, more clinically useful question: *how
much do these two methods actually disagree, in absolute terms, and does
that disagreement change depending on the value being measured?* It does
this with a specific re-plotting trick:

- **x-axis: the mean of the two measurements**, `(predicted + groundTruth) / 2`
  — a stand-in for "the best available estimate of the true value," since a
  real ground-truth device (a pulse oximeter, a contact PPG sensor) is
  itself not perfectly noise-free.
- **y-axis: the difference between the two measurements**, `predicted - groundTruth`
  — the actual disagreement, in the original units (bpm or SpO2%), not
  hidden inside a correlation coefficient.

Three horizontal reference lines complete the picture:

- **Bias** (the mean of all the differences) — is there a systematic
  tendency to over- or under-estimate?
- **Upper and lower limits of agreement** (`bias ± 1.96 × SD` of the
  differences) — the range within which about 95% of individual
  disagreements are expected to fall, under the standard assumption that
  the differences are roughly normally distributed.

::: pitfall
**Common beginner mistake.** Looking only at the correlation coefficient
and concluding "high r means the method is accurate." A method can be
consistently 5 bpm too high on every single subject and still produce an
r very close to 1.0, because r only measures whether the two variables rise
and fall together — it is blind to a constant offset. Segment 6's own HR
results (see the Line-by-Line doc) show exactly this: CHROM/POS land an r
of 0.995 on the pooled VIPL subjects while still carrying a real ~4 bpm
average error. Bland-Altman's bias line is what catches that a bare
correlation number would hide.
:::

::: pausecheck
**Pause and check yourself.** If a method's Bland-Altman plot showed a bias
line sitting exactly at zero, but very wide limits of agreement (say,
±20 percentage points for SpO2), would you call that method accurate? What
does "zero average bias" actually guarantee, and what does it *not*
guarantee, about any single individual prediction?
:::

# Why Pooling UBFC and VIPL for SpO2 Calibration Is the Right Move

`spo2/calibrateSpO2.m` fits a straight line, `SpO2 = A - B*R`, from
whatever `(R, SpO2)` pairs it is handed. A linear fit's reliability depends
overwhelmingly on how many independent data points it has to learn from —
5 points (Segment 5's DATASET_1-only attempt) is barely enough to define a
line at all, and Segment 5's own results showed exactly this instability:
the fitted slope's sign flipped depending on which single subject was held
out.

The natural instinct is to worry that UBFC and VIPL are different enough
(different cameras, different lighting, different populations) that mixing
them "contaminates" the calibration. This instinct gets the tradeoff
backwards for a **linear ratio-of-ratios calibration specifically**: what
kills this kind of fit is not moderate cross-dataset heterogeneity — it is
having too few independent subjects to average that heterogeneity out over.
More independent subjects, even somewhat different ones, is exactly what
turns an unstable, sign-flipping 5-subject line into a more stable 8+
subject line. This is not a hand-wave — Segment 6's own pooled result
(1.23 percentage points pooled MAE, physiologically-correct-direction
Pearson r of -0.755) is measurably tighter than Segment 5's DATASET_1-only
result (1.97 points, unstable slope sign), and the only thing that changed
between the two is 3 more pooled subjects.

::: intuition
**Intuition first.** Estimating the average height of a population from 5
people, all from one city, gives you a shaky number that could easily be
thrown off by one unusually tall or short person in that small sample.
Estimating it from 8 people across two different cities gives you a more
stable number, even though the two cities aren't identical — because the
extra independent data points do more to cancel out random sampling noise
than the cities' real differences do to bias the average. The same
arithmetic applies to fitting a line through noisy points: more independent
points beats a smaller, purer sample, up to the point where the *sources*
themselves are so different they represent genuinely different physical
relationships (not the case here — both datasets are the same red/blue
ratio-of-ratios measured on human facial skin under ordinary lighting).
:::

**This does not mean dataset differences are irrelevant.** Segment 6 pools
UBFC and VIPL for the *fit itself* (a leave-one-out fold's training set is
genuinely drawn from both datasets together) precisely because a linear
model with only two free parameters (`A`, `B`) cannot afford to throw away
independent training subjects — but Segment 6 also reports **per-dataset
breakdowns** (`results/metrics/segment6_spo2_loso_metrics.csv`'s `UBFC` and
`VIPL` scope rows) specifically so the team can check whether accuracy
holds up consistently across both datasets or quietly diverges on one of
them. Pooling for training and still reporting per-source accuracy
separately are not in tension — they answer two different, both useful,
questions.

::: pausecheck
**Pause and check yourself.** Segment 6's per-dataset SpO2 breakdown shows
UBFC's MAE (1.22 points) and VIPL's MAE (1.24 points) landing very close to
each other. If instead one dataset's MAE had come out dramatically worse
than the other's (say, 1.2 points for UBFC vs. 6 points for VIPL), would
that be a reason to *stop* pooling them for the fit, or would it instead
point toward a different, more specific problem to investigate first? What
would you check before concluding "these datasets shouldn't be pooled"?
:::

# The Calibrated-vs-Uncalibrated Distinction

This project's two vital signs sit on genuinely different footing, and
Segment 6's evaluation design reflects that honestly rather than papering
over it:

- **Heart rate is uncalibrated** — `heartrate/fftHeartRate.m` reads a
  frequency peak directly off a spectrum. Nothing about it is fit to any
  subject's ground truth, ever. There is no parameter to leak, so HR is
  pooled across every available subject and scored directly with
  `validation/computeMetrics.m` — no held-out folds needed or appropriate.
- **SpO2 is calibrated** — `spo2/calibrateSpO2.m`'s `A` and `B` are learned
  from ground-truth data. Evaluating a calibrated model without holding
  subjects out is a well-known way to produce artificially optimistic
  numbers, because the model can partially "memorize" the very subjects
  it's being tested against. `validation/runLOSO.m` exists specifically to
  prevent this: every fold refits fresh on every other pooled subject
  before ever touching the held-out one.

Reporting both with the *same* MAE/RMSE/Pearson-r/Bland-Altman toolkit,
while being explicit that they were produced by two different validation
procedures for a real, physically-grounded reason, is more honest than
either (a) applying LOSO to HR unnecessarily (padding out a report with
folds that don't change anything, since there is nothing to leak), or
(b) skipping LOSO for SpO2 to save effort (silently accepting leaked,
overly optimistic numbers).

# How This Maps Onto Dr. Hasan's Live Defense-Day Comparison

On defense day, the plan is a live, in-person comparison: Dr. Hasan's own
pulse oximeter against this project's camera-based app, read in real time,
side by side. It is worth recognizing explicitly what that live comparison
actually *is*, statistically: it is a Bland-Altman-style comparison with
**N = 1**.

One subject (Dr. Hasan himself, or whoever volunteers), one pair of
readings (the app's estimate, the oximeter's reading) at one moment in
time, produces exactly one point: one `mean` value, one `diff` value. That
single point can be plotted on the exact same axes as every point in
`results/figures/segment6_spo2_bland_altman_pooled.png`, and it will either
fall inside this project's own measured limits of agreement or it won't.

::: pausecheck
**Pause and check yourself.** If the live defense-day reading falls
*outside* the pooled limits of agreement measured in Segment 6 (an unlucky
but entirely possible outcome with a system trained on only 8 subjects),
does that automatically mean the method is broken? What would N=1 be
capable of proving or disproving on its own, versus what the pooled 8-point
Bland-Altman study is capable of? (Hint: re-read what "95% of individual
differences are expected to fall inside these two lines" actually implies
about the other roughly 5%, and what a single sample can and cannot tell
you about a distribution.)
:::

This is exactly why Segment 6's numbers, and this document's own repeated
insistence on stating N honestly, matter for the defense specifically: a
single live comparison is real evidence, but it is statistically the
thinnest possible amount of it — one draw from the same distribution
Segment 6's 8-subject (SpO2) or 3-subject (HR, today) pooled study is
already trying to characterize. Walking in with the pooled Bland-Altman
plot and limits of agreement already in hand means a single live
reading — good or bad — can be explained and contextualized on the spot,
rather than treated as the entire verdict on the project.

# Segment 4 — Line-by-Line Explanation

This document walks through `matlab/src/pulseextraction/chromCombine.m`,
`matlab/src/pulseextraction/posCombine.m`, and
`matlab/src/heartrate/fftHeartRate.m` block by block, in plain teaching
language. It assumes you've just finished Chapters 6-7 of the project's
Orientation Lecture (FFT heart rate, the frequency-resolution tradeoff tied
to STFT, and the CHROM/POS formulas) but haven't seen this specific
implementation before. The code files themselves are deliberately bare of
inline comments — this document is where the *why* lives, exactly as it
was for Segments 2 and 3.

---

## Part 0 — The One Judgment Call You Need to Understand First

Both `chromCombine.m` and `posCombine.m` take **more arguments than the
original stub declared.** The stub said:

```matlab
function pulseSignal = chromCombine(R, G, B)
```

The shipped version says:

```matlab
function pulseSignal = chromCombine(R, G, B, RRaw, GRaw, BRaw)
```

This wasn't a casual change — it's the direct result of a real numerical
problem the task brief itself flagged, and it's worth understanding
*before* reading the rest of this document, because it explains half the
lines in both files.

CHROM and POS both start by normalizing each color channel by its own
temporal mean:

```
Rn = R / mean(R)
Gn = G / mean(G)
Bn = B / mean(B)
```

The point of this step is to cancel out **overall brightness** — how
bright this particular subject's skin is, how bright the room's lighting
is — so that what's left (`Rn`, `Gn`, `Bn`) reflects only the *shape* of
each channel's variation over time, not its absolute scale. That's what
makes CHROM/POS more robust across subjects and lighting conditions than
just picking one raw channel.

The catch: by the time Segment 4 runs, `R`, `G`, `B` are **already**
`R_filtered`, `G_filtered`, `B_filtered` — the *output of Segment 3's
`bandpassClean.m`*. A bandpass filter's whole job is to reject the 0 Hz
(DC) component. That means `mean(R_filtered)` is not a meaningful
brightness level at all — it's a number extremely close to zero (on the
order of `1e-10` to `1e-3`, depending on numerical rounding), left over
only from filter edge effects. Dividing by that number is numerically
unstable: it can blow `Rn` up to a huge value, or even flip its sign,
depending on which way that near-zero mean happens to round. Using it as
literally written would silently produce garbage, not an error — exactly
the kind of "ran fine, wrong answer" bug this project's earlier segments
have been careful to avoid.

::: pitfall
**Common beginner mistake.** It's tempting to read "Rn = R / mean(R)" and
just plug in whatever variable happens to be called `R` in scope — in
this case, `R_filtered`. The formula is correct; the *input* to feed it
is the trap. Always ask what a filtered signal's own mean actually
represents (here: almost nothing, since the filter design specifically
targets removing that component) before dividing by it.
:::

The fix: both functions accept the **raw, pre-filter** channel traces
(`RRaw`, `GRaw`, `BRaw` — i.e. `R`, `G`, `B` straight out of
`data/processed/<subjectID>_rgb_traces.mat`, Segment 2's output, before
any detrending or filtering) purely so they can compute
`mean(RRaw)`, `mean(GRaw)`, `mean(BRaw)` — genuine, physically meaningful
average pixel-brightness levels — and use *those* as the normalization
denominator, while still combining the actual filtered signals
(`R`, `G`, `B` in the function body) for `Xs`/`Ys`/`S1`/`S2`. This is
exactly what published CHROM implementations do in spirit: normalize the
pulsatile ripple by the skin's DC brightness level, not by the ripple's
own (near-zero) mean.

`run_segment4_heartrate_batch.m` loads both `.mat` files for this exact
reason — `_filtered_traces.mat` for the signals actually being combined,
and `_rgb_traces.mat` for the raw means alone.

::: pausecheck
**Pause and check yourself.** Why is `mean()` of a bandpass-filtered
signal expected to be close to zero regardless of what the *unfiltered*
signal's brightness level was? (Hint: think about what a bandpass
filter's frequency response looks like exactly at 0 Hz.)
:::

---

## Part 1 — `chromCombine.m`

### Signature

```matlab
function pulseSignal = chromCombine(R, G, B, RRaw, GRaw, BRaw)
```

`R, G, B` are the filtered channels being combined; `RRaw, GRaw, BRaw`
exist solely to supply a physically meaningful mean, as covered in Part 0.

### Normalization

```matlab
meanRRaw = mean(RRaw);
meanGRaw = mean(GRaw);
meanBRaw = mean(BRaw);

Rn = R / meanRRaw;
Gn = G / meanGRaw;
Bn = B / meanBRaw;
```

Three scalar means, computed once from the raw traces, then used to scale
the filtered traces. Note `R / meanRRaw` divides an entire vector by a
scalar — ordinary MATLAB scalar division, applied element-wise
automatically, exactly matching the way the formula was given in the task
brief (`Rn = R_filtered / mean(R_filtered)`, just with a different, valid
mean substituted in).

### The chrominance combination itself

```matlab
Xs = 3*Rn - 2*Gn;
Ys = 1.5*Rn + Gn - 1.5*Bn;
```

`Xs` and `Ys` are two different fixed linear combinations of the
normalized channels. These particular coefficients (3, -2, 1.5, 1, -1.5)
come from the published CHROM algorithm (de Haan & Jeanne, 2013) — they
are derived from a model of how human skin reflects light and how a
blood-volume pulse modulates that reflection differently in each color
channel. The intuition, not just the algebra: as blood volume rises and
falls with each heartbeat, it changes the red, green, and blue channels
by *different relative amounts*, because oxygenated blood absorbs red and
green light differently than it absorbs blue light. `Xs` and `Ys` are two
specific combinations chosen so that ambient-lighting changes and motion
artifacts affect both `Xs` and `Ys` in a highly correlated way, while the
genuine pulse signal affects them differently — which is exactly what the
next step exploits.

::: intuition
**Intuition first.** Picture the skin's color as a moving point in 3D
RGB space. Most of what moves that point around from frame to frame —
someone shifting slightly, a lighting flicker, camera auto-exposure — is
motion along one particular direction (the "skin-tone vector"): the color
changes, but the ratio of R, G, B roughly holds. `Xs` and `Ys` are built
to look nearly identical to each other along exactly that motion
direction, so it cancels out when you compare them. The blood pulse, by
contrast, moves the color point along a *different* direction — because
it affects each channel by different physical amounts. That difference in
direction is what CHROM is designed to isolate.
:::

### Combining `Xs` and `Ys` into one signal

```matlab
alpha = std(Xs) / std(Ys);

pulseSignal = Xs - alpha*Ys;
```

If `Xs` and `Ys` were combined with equal weight (`Xs - Ys`), any leftover
motion/lighting artifact still present in both (in different amounts)
wouldn't fully cancel. `alpha` rescales `Ys` so its *overall variability*
(standard deviation) matches `Xs`'s before subtracting — this is a
data-driven way of balancing the two signals' amplitudes without needing
to know the exact lighting/motion conditions in advance. Subtracting the
rescaled `Ys` from `Xs` cancels the shared (motion/lighting) component and
leaves mostly the pulse-driven difference between the two.

::: pausecheck
**Pause and check yourself.** If a recording had unusually large motion
artifacts throughout (not just a brief bump), would you expect `alpha` to
come out larger or smaller than for a nearly still recording, and why does
that make sense given what `alpha` is trying to balance?
:::

---

## Part 2 — `posCombine.m`

### Signature

```matlab
function pulseSignal = posCombine(R, G, B, frameRate, RRaw, GRaw, BRaw)
```

Same `R/G/B` and `RRaw/GRaw/BRaw` roles as CHROM. `frameRate` is carried
over from the original stub (the published POS algorithm normally runs
this whole combination over a short sliding window, e.g. ~1.6 seconds,
sized from the frame rate, and repeats it as the window slides across the
recording). **This project's Segment 4 brief specifies the simpler
whole-signal formula below instead** — the same non-windowed approach
CHROM uses — so `frameRate` is accepted for signature compatibility and
possible future windowed extension, but the current implementation does
not use it. This is a deliberate simplification, not an oversight — see
the Guideline PDF for the pitfall this could later cause on a much longer
recording.

### Normalization

Identical in structure to CHROM's — same reasoning from Part 0 applies
here without repeating it:

```matlab
meanRRaw = mean(RRaw);
meanGRaw = mean(GRaw);
meanBRaw = mean(BRaw);

Rn = R / meanRRaw;
Gn = G / meanGRaw;
Bn = B / meanBRaw;
```

### The POS combination itself

```matlab
S1 = Gn - Bn;
S2 = Gn + Bn - 2*Rn;

pulseSignal = S1 + (std(S1)/std(S2))*S2;
```

POS (Wang et al., 2017) takes a different pair of projection directions
than CHROM (`S1`, `S2` instead of `Xs`, `Ys`), derived from a more
general analysis of how skin-tone variation is constrained to a plane in
RGB space, with the pulse direction orthogonal to it within that plane.
`S1 = Gn - Bn` and `S2 = Gn + Bn - 2*Rn` are the two specific directions
POS's derivation identifies as spanning that plane in a way that isolates
the pulse component well.

`std(S1)/std(S2)` plays exactly the same role as CHROM's `alpha` — scale
`S2` to match `S1`'s variability before combining, so the combination
isn't dominated by whichever of the two happens to have larger raw
amplitude for reasons unrelated to the pulse.

::: intuition
**Intuition first.** Both CHROM and POS follow the same two-step recipe:
(1) build two different fixed linear combinations of the normalized
channels, each designed so that non-pulse variation (motion, lighting)
shows up in both combinations in a correlated way while the pulse doesn't;
(2) rescale one combination to match the other's overall energy, then
subtract (CHROM) or add (POS) them to cancel the shared part. They differ
in exactly which two combinations they use and the algebraic sign of the
final step — but the underlying strategy, and the reason both usually beat
a single raw channel, is the same.
:::

Why does this project run *both* CHROM and POS on every subject, rather
than picking one? Because on real (imperfect, motion-affected) UBFC-rPPG
footage, neither algorithm dominates the other in every case — having two
independent HR estimates, plus the raw green-channel estimate, gives
Segment 6's validation stage more evidence for which approach actually
performs best on this project's specific data, rather than assuming it
from the literature alone.

---

## Part 3 — `fftHeartRate.m`

### Signature

```matlab
function [hrBpm, freqSpectrum, powerSpectrum] = fftHeartRate(pulseSignal, frameRate)
```

Works on any 1-D signal — the re-filtered CHROM output, the re-filtered
POS output, or `G_filtered` directly (no combination at all), which is
exactly how `run_segment4_heartrate_batch.m` uses it three times per
subject.

### Taking the FFT and keeping only the useful half

```matlab
signalLength = length(pulseSignal);
fftResult = fft(pulseSignal);

numPositiveBins = floor(signalLength / 2) + 1;
fftPositive = fftResult(1:numPositiveBins);
```

`fft()` of a real-valued signal is symmetric: the second half of its
output is just a mirror image (complex conjugate) of the first half and
carries no extra information for a real input. Keeping only
`1:numPositiveBins` (from 0 Hz up to the Nyquist frequency) discards
exactly that redundant mirrored half — nothing about the signal is lost,
it's just not duplicated.

### Turning bin indices into real frequencies — never a hardcoded number

```matlab
freqResolution = frameRate / signalLength;
freqSpectrum = (0:numPositiveBins - 1) * freqResolution;
```

This is the single most important pair of lines in this file, for the
same reason `bandpassClean.m`'s Nyquist calculation was the most important
lines in Segment 3: **frequency resolution depends on both the sampling
rate and the number of samples**, and both of those vary per subject (UBFC
frame rates aren't a clean 30 fps, and clip lengths differ). `bin k`
corresponds to `k * (frameRate / signalLength)` Hz — hardcoding a
resolution assumed from "a typical 30 fps, 2000-ish-frame clip" would put
every bin's frequency label very slightly wrong for any subject whose
actual `fs`/length differs, with no error to signal it.

```matlab
powerSpectrum = abs(fftPositive);
```

`fft()` returns complex numbers (magnitude and phase). Heart-rate
estimation only cares about *how much* energy is at each frequency, not
its phase, so `abs()` reduces each complex bin to a single magnitude
value. (Despite the variable being named `powerSpectrum` — inherited from
the original stub's naming — this holds the FFT *magnitude*, `|FFT|`, not
squared power; that's what the mandatory sanity plot in Step 6 of the
batch script needs directly, and squaring vs. not squaring doesn't change
*where* the peak is, which is all that matters for peak-picking below.)

### Restricting the search to the physiological band *before* peak-picking

```matlab
lowBandHz = 0.7;
highBandHz = 4.0;
bandMask = freqSpectrum >= lowBandHz & freqSpectrum <= highBandHz;

freqInBand = freqSpectrum(bandMask);
powerInBand = powerSpectrum(bandMask);
```

This is the step the task brief specifically warned about: **find the
global peak and hope it's in range** is not what this code does.
`bandMask` is built and applied *before* any peak search happens, so a
strong noise spike at, say, 6 Hz (outside any physiologically possible
heart rate) can never win. This matters even though the input has already
been through `bandpassClean.m` — a Butterworth filter attenuates
out-of-band content heavily but not to literally zero, and combining
channels (CHROM/POS) can reintroduce a small amount of out-of-band energy
too (which is exactly why Step 3 of the pipeline re-filters after
combination, before this function ever sees the signal). Masking the
search band is a second, independent safety net on top of that filtering,
not a replacement for it.

::: pitfall
**Common beginner mistake.** Writing `[peakPower, peakIndex] =
max(powerSpectrum)` on the *full* spectrum, then converting that index to
a frequency, and only afterward checking whether it happens to land in
0.7-4 Hz. On a noisy or short recording, the strongest peak in the whole
spectrum is not guaranteed to be inside the valid band — a residual
near-0 Hz drift component or a burst of high-frequency noise can easily
out-muscle the real (and often comparatively modest) pulse peak if the
band restriction is applied as an afterthought instead of a mask on the
search itself.
:::

### From the masked spectrum to a heart rate in bpm

```matlab
peakPower = max(powerInBand);
peakIndex = find(powerInBand == peakPower, 1);
peakFreqHz = freqInBand(peakIndex);

hrBpm = peakFreqHz * 60;
```

`max(powerInBand)` finds the largest magnitude *within* the already-masked
band; `find(..., 1)` locates the first bin matching that value (relevant
only in the rare case of an exact tie); `freqInBand(peakIndex)` converts
that bin position back to a frequency in Hz. The final `* 60` converts
Hz to bpm (60 seconds per minute) — the same conversion Segment 3's
Guideline PDF used going the other direction (bpm to Hz, to pick the
0.7-4 Hz cutoffs in the first place).

### The frequency-resolution tradeoff, in concrete numbers for this dataset

This is the STFT-adjacent tradeoff flagged in the Orientation Lecture:
**a longer signal gives finer frequency resolution, a shorter signal gives
coarser resolution** — the same window-length-vs-resolution tradeoff that
applies to any windowed spectral estimate, FFT included, since a single
FFT over the whole clip is really just a one-window STFT.

`freqResolution = frameRate / signalLength` is the size of one FFT bin in
Hz. For the three DATASET_1 subjects used to verify this segment
(`fs ≈ 28.67` fps, clip lengths 2362-2409 frames, i.e. ~82-84 second
recordings):

```
freqResolution ≈ 28.67 / 2400 ≈ 0.0119 Hz  →  0.0119 * 60 ≈ 0.71 bpm per bin
```

In other words, for a UBFC-rPPG-length clip, the FFT can only report a
heart rate to about **the nearest 0.7 bpm** — finer-looking decimal
output (like `76.4105`) is real in the sense that it's exactly which bin
won, but the true achievable *precision* of this method on this data is
closer to "plus or minus a bin or so," not a fraction of a bpm.

::: pausecheck
**Pause and check yourself.** If a teammate ran this same code on a much
shorter, 10-second self-collected test clip instead of an 80-second UBFC
clip (same ~29 fps), roughly how much would the bpm resolution get worse,
and would you still trust individual bpm estimates to one decimal place?
:::

**Why CHROM and POS report the exact same bpm on the subjects tested
here.** Running the batch script on `5-gt`, `6-gt`, `7-gt` produces
`HR_chrom == HR_pos` to four decimal places for all three. This looks
suspicious at first glance but is not a bug — it was checked directly by
comparing the two combined signals sample-by-sample: they are *not*
identical (`max(abs(chromSignal - posSignal))` is small but nonzero), they
are just very strongly correlated (both are linear combinations of the
same three highly-correlated color channels, both specifically designed
to isolate the same underlying cardiac frequency). With a bin resolution
of ~0.7 bpm, two signals that both have their true dominant frequency
sitting well inside the same bin will report identical `hrBpm`, even
though the full-precision continuous-frequency answer would differ
slightly between them. This is expected behavior given the resolution
ceiling above, not evidence the two algorithms collapsed into the same
computation.

---

## How This Segment Feeds Into Segment 6

Every subject processed by `run_segment4_heartrate_batch.m` produces three
independent bpm estimates — `HR_chrom`, `HR_pos`, `HR_green` — saved both
per-subject (`data/processed/<subjectID>_hr_estimates.mat`) and as one row
in the shared `results/metrics/segment4_hr_summary.csv`. Segment 6's
formal leave-one-subject-out validation (`validation/runLOSO.m`,
`validation/computeMetrics.m`, both still untouched stubs) is where these
three estimates get systematically compared against ground truth across
every available subject, with proper MAE/RMSE/correlation statistics. What
this segment provides is the raw material for that comparison — not the
comparison itself. The `abs_error_*` columns in this segment's CSV are a
quick eyeball check for individual subjects, not a substitute for
Segment 6's formal metrics pipeline.

# Segment 3 — Line-by-Line Explanation

This document walks through `matlab/src/filtering/detrendSignal.m` and
`matlab/src/filtering/bandpassClean.m` block by block, in plain teaching
language. It assumes you've just finished Chapter 5 of the project's
Orientation Lecture (detrending, bandpass filtering, why `filtfilt`
matters) but haven't seen this specific implementation before. The code
files themselves are deliberately bare of inline comments — this
document is where the *why* lives, exactly as it was for Segment 2.

---

## Part 1 — `detrendSignal.m`

### What the function is for

Segment 2 handed us three raw signals, `R(t)`, `G(t)`, `B(t)` — the
spatially-averaged pixel brightness of a forehead patch, one value per
video frame. Buried inside each of those traces is the pulse we actually
want, but it's riding on top of a much bigger, much slower wandering
baseline: the room's lighting drifting slightly, the subject's overall
skin tone shifting a little as they settle into position, the automatic
exposure/white-balance of the camera nudging brightness up or down over
tens of seconds. None of that has anything to do with a heartbeat.
`detrendSignal.m`'s whole job is to estimate that slow-moving baseline
and subtract it off, leaving a signal that oscillates around zero.

### The function signature

```matlab
function [signalDetrended, detrendOrder] = detrendSignal(signalRaw)
```

The stub this was built from only declared one output,
`signalDetrended`. A second output, `detrendOrder`, was added on top of
that (backward-compatible — any code that only asks for one output still
works exactly as before, it just won't see the second). This mirrors the
same pattern used in Segment 2's `extractROISignals.m`, which grew extra
trailing outputs (`droppedFrameIdx`, `debugFrame`) for exactly the same
reason: `scripts/run_segment3_filtering_batch.m` needs to record which
polynomial order was actually used, without hardcoding a second copy of
that number in the batch script and hoping it never drifts out of sync
with the real one inside this function. Returning it directly makes that
impossible to get wrong.

### The two lines that do the actual work

```matlab
detrendOrder = 3;
signalDetrended = detrend(signalRaw, detrendOrder);
```

**Why polynomial detrending, and why the built-in `detrend()` instead of
writing `polyfit`/`polyval` by hand.** The task allowed either approach.
`detrend(x, n)` does exactly what a hand-rolled version would: fit an
`n`th-degree polynomial to `x` by least squares, then subtract that
polynomial from `x` at every sample. Using the built-in is simply less
code that does the same well-understood, well-tested thing — there's no
hidden behavior to be suspicious of, and it's the standard MATLAB tool
built for precisely this job. Writing `polyfit`/`polyval` manually
here would just be re-implementing `detrend()` badly.

**Why order 3 specifically.** This is the one number in this file that
actually matters, so it's worth justifying carefully rather than just
picking something that "felt reasonable":

- **Order 0 or 1** (just removing the mean, or the mean plus a straight
  linear ramp) is the simplest possible choice, but it only captures a
  *constant* rate of drift. Real illumination drift over a 60-90 second
  UBFC-rPPG recording is rarely a perfectly straight line — a cloud
  passing overhead, or the camera's auto-exposure settling in over the
  first several seconds, produces a curve, not a line. A linear fit
  would leave a visible curved residual behind.
- **Order 3 (cubic)** gives the fit enough flexibility to bend and
  follow a smooth, gently curving illumination trend, without having so
  many degrees of freedom that it starts trying to follow the actual
  pulse oscillations.
- **A much higher order (say, 8 or 10)** would be a mistake — with
  enough polynomial terms, the fit can start wiggling fast enough to
  track the ~1 Hz pulse ripple itself, and subtracting *that* would
  delete the very signal this whole project is trying to measure. This
  is a genuine trap: more flexibility is not automatically better here.

The deciding argument for why order 3 stays safely on the "slow drift
only" side of that line is a frequency-domain one: a degree-3 polynomial
fit to a signal spanning `T` seconds has almost all of its energy at
frequencies on the order of `1/T` Hz or lower — for an 80-second UBFC
recording, that's roughly 0.01-0.04 Hz. The pulse band this project
cares about starts at 0.7 Hz (42 bpm) — more than an order of magnitude
higher. A cubic trend simply cannot oscillate fast enough to bite into
the pulse band, no matter how the illumination happens to drift during
that recording. That gap is the real justification, not just "3 seemed
about right."

`signalRaw` here is a `1 x N` row vector (Segment 2's `R`, `G`, `B` are
all `1 x numFrames`). `detrend()` preserves whatever orientation you
give it, so `signalDetrended` comes back as a `1 x N` row vector too —
no reshaping needed.

---

## Part 2 — `bandpassClean.m`

### What the function is for

Detrending removes the slow stuff *below* the pulse band. But there's
also noise *above* the pulse band — camera sensor noise, small motion
jitter, anything faster than a heartbeat physically can be. A heart rate
of 40-240 bpm converts to 0.667-4 Hz (dividing bpm by 60), which this
project rounds to a clean 0.7-4 Hz working band. `bandpassClean.m`'s job
is to keep only that band and discard everything outside it, in both
directions at once — that's what makes it a *band*pass filter rather
than just a low-pass or high-pass.

### The function signature

```matlab
function [signalFiltered, filterOrder] = bandpassClean(signalDetrended, frameRate)
```

Same reasoning as `detrendSignal.m` above: the stub declared one output,
and a second (`filterOrder`) was added so the batch script can record
which Butterworth order was actually used, straight from the source of
truth, rather than a second hardcoded copy that could silently drift out
of sync.

### Computing the cutoffs from the *actual* frame rate

```matlab
filterOrder = 2;
lowCutoffHz = 0.7;
highCutoffHz = 4.0;
nyquistHz = frameRate / 2;
lowCutoffNormalized = lowCutoffHz / nyquistHz;
highCutoffNormalized = highCutoffHz / nyquistHz;
```

MATLAB's `butter()` doesn't take cutoff frequencies in Hz directly — it
wants them **normalized to the Nyquist frequency**, i.e. as a fraction
between 0 and 1, where 1.0 means "half the sampling rate." That
normalization is exactly `cutoffHz / (frameRate / 2)`.

This is the single most important line in this whole segment, and it's
worth being explicit about why: `frameRate` here is **not** a constant —
it's the argument passed in, which traces all the way back to
`VideoReader.FrameRate` read directly from each subject's own video file
in `loadUBFCVideo.m`. `docs/DATA_FORMAT.md` confirms UBFC-rPPG videos
run anywhere from about 28.6 to 29.8 fps, and the exact value differs
per subject. If this function hardcoded, say, `nyquistHz = 15` (assuming
a flat 30 fps), the normalized cutoffs computed from that wrong number
would put the actual passband at very slightly the wrong place in Hz for
every subject whose real fs isn't exactly 30. The filter would still
*run* without any error — it just wouldn't be filtering exactly the band
it claims to be filtering, a mistake that produces no crash, no warning,
and a subtly wrong result that's easy to miss. Computing `nyquistHz`
fresh from the `frameRate` argument every single call eliminates that
entire failure mode.

**Why 0.7-4 Hz and not exactly 0.667-4 Hz.** 40-240 bpm converts to
0.667-4 Hz exactly. This project (like most published rPPG work) rounds
the low edge up slightly to 0.7 Hz — a small, deliberate safety margin
below the band edge, both because filters don't cut off perfectly
sharply (there's always some rolloff, not a vertical wall) and because
resting heart rates essentially never dip anywhere near 40 bpm in this
dataset, so nothing physiologically relevant is lost by that margin.

### Why order 2 (not higher)

`filterOrder = 2` is passed to `butter()`. One subtlety worth being
explicit about: when you ask `butter()` for a `'bandpass'` filter with
order `N`, the filter you actually get back has an *effective* order of
`2N` — a bandpass is built internally as a combination of a highpass and
a lowpass transformation of the base lowpass prototype, which doubles
the number of poles. So `filterOrder = 2` here produces a 4th-order
Butterworth bandpass filter in practice, which sits right in the "2nd to
4th order, don't over-order it" range this segment was asked to justify.

Why not go higher (order 4, 6, 8...)? A higher-order Butterworth filter
has a steeper rolloff at the band edges — it rejects out-of-band content
more aggressively — but that steepness comes at a real cost: steeper
filters also distort the *shape* of what's left inside the passband more
(more ringing, more overshoot near sharp features), and they're more
prone to numerical instability, especially combined with narrow
passbands like 0.7-4 Hz relative to a ~15 Hz Nyquist frequency. Since
this project's later SpO2 stage cares about the precise *amplitude
shape* of the pulse waveform (not just "is there a periodic signal
somewhere in this band," which is all FFT-based heart rate needs), an
aggressively steep, potentially ringing filter is actively
counterproductive here. A low order that does a clean, gentle job is the
right trade-off, not a limitation to work around.

### `filtfilt`, not `filter` — and why it specifically matters here

```matlab
[filterCoeffB, filterCoeffA] = butter(filterOrder, [lowCutoffNormalized, highCutoffNormalized], 'bandpass');
signalFiltered = filtfilt(filterCoeffB, filterCoeffA, signalDetrended);
```

`butter()` returns the filter's coefficients (`filterCoeffB`,
`filterCoeffA` — the numerator and denominator of the filter's transfer
function). Those coefficients alone don't filter anything; they have to
be applied to the actual signal, and that's where the `filter()` vs.
`filtfilt()` choice matters enormously.

`filter()` applies the filter once, moving forward through the signal
sample by sample. Every real (non-trivial) digital filter introduces a
**phase shift** — it delays different frequency components of the
signal by different amounts as it passes through. For a task like
FFT-based heart rate, where you only care about *which frequency* has
the most energy, a phase shift barely matters — the frequency content is
still there, just time-shifted. But this project's later SpO2 stage
(ratio-of-ratios, `spo2/ratioOfRatios.m`) needs to measure the AC
(pulsatile) *amplitude* of the waveform accurately, and to compare that
amplitude's timing across the red and blue channels. A phase-shifted
signal doesn't just look "delayed" — because the different color
channels can end up shifted by slightly different amounts, a naive
single-pass filter can distort the very waveform shape the SpO2
calculation depends on.

`filtfilt()` solves this by running the filter **twice**: once forward
through the signal, then again backward over the result. Every phase
shift introduced by the forward pass gets exactly cancelled by the
backward pass, because delaying something and then "un-delaying" it (by
running time backward) leaves zero net phase distortion — what's left
is a pure magnitude-only filtering effect, with the output perfectly
time-aligned to the input. The cost is that `filtfilt()` effectively
applies the filter twice (which is part of why staying at a low order
like 2 rather than 4 or 6 matters — twice-through order 2 already gives
you the sharpness of a straightforward order-4 filter, without
compounding a higher order twice over), and it needs a reasonably long
signal to pad and settle at the edges — never an issue for a ~2000+
sample UBFC-rPPG recording, but worth knowing as a general limitation of
`filtfilt()` on very short signals.

`signalDetrended` in, `signalFiltered` out — same length, same `1 x N`
orientation, now with the slow drift already removed by
`detrendSignal.m` and everything outside 0.7-4 Hz suppressed by this
filter. What's left should visually resemble a repeating, roughly
periodic pulse waveform — exactly what
`scripts/run_segment3_filtering_batch.m`'s sanity PNG is there to let a
human confirm, subject by subject, before this signal moves on to
Segment 4 (CHROM/POS combination).

# Segment 7 Task H — IIR Phase-Distortion Assessment (Action 6b)

Per Lapitan, Rogatkin, Molchanova & Tarasov ("Estimation of phase distortions of the
photoplethysmographic signal in digital IIR filtering," *Sci Rep* 2024, 14:6546,
doi:10.1038/s41598-024-57297-3), assesses whether causal-IIR phase distortion is a
measurable concern for this app's live HR display.

## The question, answered directly from the code

Read `signal/BandpassFilter.kt` and `signal/RealHeartRateEstimator.kt` before writing
anything below (not from memory/description).

**`BandpassFilter.apply()` calls `filtfilt()`, not a causal single-pass `lfilter()`.**
`filtfilt()` (lines 150-173) is a genuine, textbook zero-phase implementation: forward
`lfilter` pass → reverse the result → `lfilter` pass again → reverse back, with
odd-reflection edge padding — the file's own KDoc states this explicitly ("Zero-phase
Butterworth bandpass, matching `bandpassClean.m` exactly... Batch operation over the
whole array passed in — not a causal/streaming filter"). `RealHeartRateEstimator.update()`
confirms the same intent at the call site ("This is a BATCH operation over the whole
buffered window, not a causal/streaming filter... zero-phase `filtfilt` requires seeing
the whole window at once").

**Answer: this is the zero-phase-equivalent approach, not causal IIR.** Lapitan et al.'s
specific concern — phase distortion from a *causal* (real-time, single-pass) IIR filter
delaying different frequency components by different amounts, smearing timing-sensitive
PPG features — does not apply here **by construction**, not merely "at this app's
filter order/cutoffs." The app re-runs a full zero-phase batch filter on a rolling
25-second buffer (`SignalBuffer.WINDOW_DURATION_SECONDS = 25.0`) once per second
(`RealHeartRateEstimator.RECOMPUTE_INTERVAL_MS = 1000`), rather than filtering
sample-by-sample causally.

## Quantifying what was avoided (real numbers, not just "it's zero-phase, done")

To make this concrete rather than assert it, the group delay of a **hypothetical causal
single-pass** version of this exact filter (order 2 Butterworth bandpass, 0.7-4Hz — the
literal parameters `BandpassFilter.ORDER`/`LOW_HZ`/`HIGH_HZ` port from
`bandpassClean.m`) was computed via `grpdelay` at this app's real measured fps range:

| fs | Mean group delay, 0.7-4Hz band | Max group delay (band edge) |
|---|---|---|
| 30 Hz | 152.6 ms | 449.5 ms |
| 25 Hz | 152.0 ms | 444.9 ms |

**If this app used a causal single-pass filter instead of `filtfilt`, the live HR
estimate would lag the true signal by roughly 150ms on average and up to ~450ms at the
band edges** (frequency-dependent delay is exactly the "distortion" Lapitan et al.
describe — different in-band frequencies delayed by different amounts, not just a
constant shift). That would be a real, non-trivial fraction of a single cardiac cycle at
typical resting HR (a 75bpm cycle is 800ms long) — genuinely worth worrying about had the
app gone the causal route.

**It did not.** `filtfilt`'s zero-phase response makes this delay exactly zero by
construction, for every frequency in the band, on every recomputed window — this isn't a
number to trade off against filter order/cutoffs, it's structurally absent.

## What IS a real, different, and separate concern (not what Lapitan et al.'s paper addresses, noted for completeness)

Zero-phase filtering requires seeing the whole window at once, which is exactly why
`RealHeartRateEstimator` re-runs the full 25-second-window `filtfilt` only once per
second rather than continuously. This introduces a **display-update latency** (up to
~1 second between a real HR change and its reflection on screen) and a **window-edge
transient** (the odd-reflection padding's own approximation quality at each window's
start/end) — but these are architectural properties of a periodically-refreshed batch
computation, not phase distortion in Lapitan et al.'s sense, and are not part of what
this task was asked to assess. Noted here only so this isn't mistaken for "no timing
concerns at all in the live pipeline."

## Bottom line

**Not a measurable issue for the live HR display, and not merely a theoretical one that
happens not to matter at this app's filter order/cutoffs — it's inapplicable by
construction**, because the app never uses causal IIR filtering for the signal path
Lapitan et al.'s paper is about. No code change made or needed; this task is an
assessment only, per its own scope.

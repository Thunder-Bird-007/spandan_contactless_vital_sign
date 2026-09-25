# Segment 31 — Promote Branch 2's Waveform to the Primary "Live Signal" + UI/UX Polish

Presentation-only, like Segment 16 Task 3 before it — no change to the camera/signal
pipeline. Two related asks, done together: (1) the app's one prominent "LIVE SIGNAL" card
was showing the raw, unfiltered green-channel signal (the shared input both branches read,
not either branch's own output) and was being read as "Branch 1's live signal"; (2) a
general aesthetic pass.

## What was wrong

`activity_main.xml` had TWO signal cards stacked: a big "LIVE SIGNAL" card
(`chartView`/`SignalChartView`) showing `samples.map { it.green }` — literally the raw ROI
average before either branch's own processing — directly under the camera, and a smaller,
easy-to-miss "WAVEFORM MORPHOLOGY (BRANCH 2)" card below it showing the actual Branch 2
output (the ensemble-averaged cardiac cycle with the detected dicrotic notch, from
`MorphologyWaveformEstimator` — see Segment 19). A viewer's attention naturally lands on the
first/biggest card, so "the live signal" read as Branch 1-associated even though Branch 2
was already fully wired and rendering correctly underneath.

## What changed

- **`SignalChartView.kt` deleted** and its raw-chart card removed from
  `activity_main.xml` — confirmed unused anywhere else first (`grep -r SignalChartView
  android/` after removal: only historical doc/comment mentions remain, no code
  references). This was a deliberate choice checked with the user first (replace outright vs.
  keep the raw chart as a smaller secondary strip) — "replace it entirely" was chosen, since
  the raw chart was only ever a pre-Branch-2, pre-filtering sanity check per its own original
  KDoc.
- **Branch 2's `WaveformView` (`morphologyWaveformView`, id unchanged) promoted to the ONE
  primary "LIVE SIGNAL" card**, now in its own "hero" panel directly under the camera
  preview: label reads "LIVE SIGNAL" (what a casual viewer reads first) with a small
  "Branch 2 · filtered pulse trace" subtitle underneath (keeps the technical identity
  visible, doesn't hide it), height raised 90dp → 140dp now that it's the featured visual.
- **`WaveformView.kt` rendering pass** (purely visual — never touches the underlying signal
  data): a gradient area-fill under the line (`LinearGradient`, built in `onSizeChanged`
  since it needs real pixel dimensions), the line itself smoothed via
  quadratic-Bezier-through-midpoint instead of straight `lineTo` segments, a faint horizontal
  midline for reference, and colors moved from hard-coded hex into `colors.xml`
  (`accent_branch2` and friends) so the hero card's tinted border and the line itself share
  one source of truth.
- **Revised mid-segment to a genuine multi-cycle trace, not one averaged beat** — see its own
  section below; this is the actual shipped behavior, the single-beat version was an
  intermediate step.
- **New `bg_hero_card.xml`**: same border-layering technique as `bg_vitals_card.xml`, but
  tinted with `accent_branch2` (~30% alpha) instead of the neutral border color — a
  deliberate, subtle color cue that this is the featured card. Both card backgrounds also
  picked up a two-stop vertical gradient fill (slightly lighter at top) instead of a flat
  solid, for a touch of depth.
- **Vitals card**: small tinted heart (`ic_heart.xml`, `accent_hr` pink) and droplet
  (`ic_droplet.xml`, `accent_spo2` blue) glyphs added above each metric's caption — gives HR
  and SpO2 a distinct visual identity at a glance instead of two identical text columns.
  Standard, generic icon silhouettes (not novel designs).
- **Preview scrim**: a small purely-cosmetic gradient fade (`bg_preview_scrim_bottom.xml`) at
  the bottom of the camera preview, easing the transition into the opaque card stack below.
- Margins/radii harmonized slightly (12dp → 14dp horizontal card margins, 20dp → 21-22dp
  corner radii) across the three cards for a more consistent rhythm.

## Revision: a genuine multi-cycle trace, not one averaged beat

First pass promoted the SAME thing the old secondary card already showed
(`MorphologyWaveformEstimator.Estimate.waveform`, `EnsembleAverageBeats`'s single ensemble-
averaged cardiac cycle, fixed `[0, size-1]` domain) into the new hero card, with its notch
marker kept. User feedback, verbatim: "I don't want just a single cycle as the live signal.
I want it updating real time, showing 8-10 cycles just like a PPG monitor will do." Correct
call — one static averaged template does not read as "live," no matter how nicely it's
rendered.

**Root cause**: Branch 2's own pipeline (`estimateVitalsAndMorphology.m`'s port, read
directly before making this change) already computes a genuine multi-cycle CONTINUOUS pulse
— `AdaptiveHarmonicFilter`/`HarmonicSelectiveGaussianFilter` → `PulseExtraction.chromCombine`
→ `FixPolarity` → `ResampleUniform` — before `EnsembleAverageBeats` chops it into individual
beats and averages them down to one prototype. That continuous, polarity-corrected,
uniformly-resampled signal (`resampled.sigUniform` inside `computeNotch`) was being computed
and then thrown away, never surfaced.

**Fix**: `MorphologyWaveformEstimator.Estimate` gained a new field, `continuousWaveform` —
the SAME selected candidate's (ABPF or Gaussian, whichever `harmonicMethodUsed` names)
continuous pulse, tail-windowed to the last `CONTINUOUS_DISPLAY_SECONDS` = 8 seconds (a
deliberate, unmeasured choice — long enough for ~8-13 real cycles at a resting 60-100bpm,
short enough that a fast HR doesn't cram in an unreadable number; not A/B'd against other
window lengths this session). The existing single-beat `waveform` field is UNCHANGED and
still computed (it's unit-tested at a fixed 256-sample size by an existing test that would
have broken had it been touched) — only the UI's own choice of which field to render moved.
`WaveformView.update()`'s signature simplified from `(waveform, notchDetected,
notchPositionNormalized)` to just `(continuousWaveform)`; the per-beat notch tick/dot overlay
was removed, since a single marker position doesn't map onto a multi-cycle trace (which of
the 8-13 beats would it annotate?) — the notch DETECTION result (method + confidence) is
still fully visible via the existing status pill text next to the trace, so no information
was lost, just the per-beat visual annotation.

2 new unit tests (`MorphologyWaveformEstimatorTest.kt`): `continuousWaveform.size == 2000`
(8s × `ResampleUniform.DEFAULT_TARGET_FS`=250Hz) on a normal 25s window, and the same
assertion on a synthetic 60s window specifically to guard against a future regression that
returns the WHOLE resampled signal instead of the tail-windowed slice.

**Confirmed on-device, twice, under different real conditions** — this is the one part of
this segment that isn't just "looks fine in a screenshot":
- A capture during a noisy moment (subject's hand near their face) showed a visibly jagged,
  high-frequency trace alongside `Gaussian (α=0.15) · conf 0.02` — a near-zero confidence,
  amber/low-quality pill. This is CORRECT, not a rendering bug: the trace is honestly
  reflecting a genuinely poor-quality window, the same way a real clinical monitor shows
  visible motion-artifact garbage rather than hiding it.
- A follow-up capture ~15s later with the subject holding still, hands away, showed a clean,
  physiologically plausible multi-cycle trace — consistent systolic/dicrotic double-peaks
  per beat, visibly periodic, matching `ABPF comb · conf 0.40` (green/OK pill) and a
  displayed 62bpm HR (62bpm over 8s ≈ 8.3 cycles, consistent with the ~13-14 total peaks
  visible at ~2 peaks/cycle for a healthy dicrotic waveform shape).

Taking BOTH captures, not just the clean one, was deliberate — a single good screenshot would
not have distinguished "the multi-cycle trace works" from "the multi-cycle trace happened to
look fine once," and this project's own convention throughout (Segment 28's noise-band
findings, Segment 30's on-device crash) is to verify behavior across more than one condition
before calling something done.

## Verification

`./gradlew test` — all unit tests pass, including the 2 new ones (66 total, up from 64).
`assembleDebug` succeeded after fixing a real XML syntax error this session introduced: a
literal `--` inside several new `<!-- -->` comment bodies, which XML forbids outright (not
just a style nit — `mergeDebugResources` hard-fails on it). Fixed by switching to em dash
(`—`), matching every existing comment in this project's own XML files, which already used
that convention consistently before this segment.

On-device confirmation is covered in the "Revision" section above (that IS the final shipped
behavior); an earlier round with the intermediate single-beat version also confirmed the
layout/icons/gradient cards rendered correctly and updated live (HR 82→77bpm, SpO2
96.69%→96.72% across two captures ~5s apart) before the multi-cycle revision replaced that
card's content.

## What wasn't done

- No new automated UI/instrumentation tests were added for the view layer itself — this
  project has none for `View`/`Canvas` drawing today (its own JVM unit tests, per
  `build.gradle.kts`'s `isReturnDefaultValues` discussion throughout this project's docs,
  cannot exercise real drawing); verification here is the same "install and look at a real
  device" discipline every prior UI-facing segment (16 Task 3, this one) has used. The
  `continuousWaveform` DATA (as opposed to its rendering) IS unit-tested, in
  `MorphologyWaveformEstimatorTest.kt`.
- `CONTINUOUS_DISPLAY_SECONDS = 8.0` is an unmeasured, arbitrary choice — not A/B'd against
  other window lengths (e.g. 5s or 12s) for readability this session.
- The bottom preview scrim is subtle by design (purely cosmetic, low alpha) — if a future
  pass wants it more pronounced, `preview_scrim_bottom`'s alpha in `colors.xml` is the one
  knob to turn.
- Icon tint colors are fixed (not tied to `EstimatorStatus`) — the status pill already
  carries live state; making the icons themselves reactive too was judged likely to look
  busier, not clearer, and wasn't requested.

## Files touched

- `app/src/main/java/com/spandan/app/signal/MorphologyWaveformEstimator.kt` (new
  `Estimate.continuousWaveform` field, tail-windowed `resampled.sigUniform`; existing
  `waveform` field untouched)
- `app/src/test/java/com/spandan/app/signal/MorphologyWaveformEstimatorTest.kt` (2 new tests
  for `continuousWaveform`)
- `app/src/main/java/com/spandan/app/MainActivity.kt` (removed `chartView` wiring; passes
  `continuousWaveform` instead of `waveform`/notch params to `WaveformView`)
- `app/src/main/java/com/spandan/app/ui/WaveformView.kt` (renders the multi-cycle
  `continuousWaveform` instead of one averaged beat; gradient fill, smoothed curve, theme
  colors; notch tick/dot overlay removed)
- `app/src/main/java/com/spandan/app/ui/SignalChartView.kt` (deleted — dead code after the
  raw chart's removal)
- `app/src/main/res/layout/activity_main.xml` (raw chart card removed; Branch 2's card
  promoted to hero; icons added to the vitals card; preview scrim added)
- `app/src/main/res/values/colors.xml` (new `accent_branch2*`/`accent_hr`/`accent_spo2`/
  `surface_card_top`/`preview_scrim_*` tokens)
- `app/src/main/res/values/strings.xml` (`chart_label` removed; `morphology_label` now
  "LIVE SIGNAL"; new `morphology_subtitle`)
- `app/src/main/res/drawable/bg_hero_card.xml` (new)
- `app/src/main/res/drawable/bg_preview_scrim_bottom.xml` (new)
- `app/src/main/res/drawable/ic_heart.xml` (new)
- `app/src/main/res/drawable/ic_droplet.xml` (new)
- `app/src/main/res/drawable/bg_vitals_card.xml` (flat solid fill → subtle gradient)

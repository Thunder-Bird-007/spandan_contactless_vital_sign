# Defense Readiness Checklist

Status as of **2026-08-12**. This is the "is this ready to demo" summary --
`../README.md` is the detailed build log/history behind it.

## Standing decision (this session)

**No MATLAB-side findings from Tasks L/N/O/P are being ported into the
Android app.** The app ships the original validated pipeline: single
forehead ROI, whole-clip FFT, no windowing/continuity/multi-region logic.
Segment 6 investigated device-stratified evaluation (L), multi-region ROI
(N), detrend/adaptive-bandpass refinement (O), and windowed harmonic
continuity (P) as possible accuracy improvements on the MATLAB side, but
none of it is in this build. This is deliberate, not an oversight:
**porting late-stage experimental MATLAB logic this close to defense was
judged higher regression risk than the runway available to re-verify it
on-device.**

---

## Action 1 — Current app state, inspected before any changes

Findings below are from reading the actual committed source (not from
memory/description of prior sessions), against `matlab/src/roi/extractROISignals.m`
and the Android sources directly.

- **`RealHeartRateEstimator` was already live**, not just present in the
  codebase. `MainActivity.kt` instantiated it (`private val heartRateEstimator
  = RealHeartRateEstimator()`) and called `.update(samples)` every UI refresh
  tick, displaying the result via `hr_format`/`hr_placeholder_default`. This
  was true before this session's changes and remains true after.
- **SpO2 was still live and fake, and its label was already accurate --
  it just hadn't been decided to remove it yet.** `MainActivity.refreshUi()`
  called `PlaceholderVitalsEstimator.computeSpo2Placeholder()` every tick and
  displayed it in a dedicated `spo2Text` view, with an honest
  "● PLACEHOLDER — not real" chip next to it (`spo2StatusText` /
  `spo2_status_placeholder`) distinct from HR's "● LIVE" chip. So the specific
  failure mode this action was checking for -- a stale "PLACEHOLDER VALUES"
  banner now misrepresenting a real HR -- **did not exist**: the two fields
  already had independent, correctly-labeled status chips from an earlier
  task. What this session changed was a *further* decision (see Action 2):
  not just labeling the fake number honestly, but removing it entirely.
- **`RoiCalculator.kt`'s placeholder TODO was a real gap, not stale
  documentation** -- see Action 5 below.
- **Correction to one "known open item" as originally briefed**: the claim
  that "the real pipeline has never been stability-tested on hardware" is
  **not fully accurate** per `../README.md`'s own history. The real
  (`RealHeartRateEstimator`) pipeline has multiple documented, crash-free
  on-device runs: ~13+ minutes combined (HR port verification), 5m15s
  (window-length follow-up), and ~2.5 minutes (switching-estimator
  follow-up) -- all logged with zero `AndroidRuntime`/`FATAL` entries. What
  had **not** happened yet was a single **continuous 15+ minute** run, which
  is what Action 4 below specifically adds. Flagging this discrepancy
  plainly rather than silently accepting the original framing.

## Action 2 — SpO2 UI: removed entirely — ✅ Done

Not relabeled, not swapped for a different placeholder -- deleted:

- `signal/PlaceholderVitalsEstimator.kt` deleted (`git rm`). Its
  `computeHeartRatePlaceholder()` was already dead code (unused since the
  real HR port); `computeSpo2Placeholder()` was the only remaining live
  caller, now gone too.
- `MainActivity.kt`: removed the `spo2Text` field, the import, and the
  `refreshUi()` block that computed/displayed SpO2. Also removed
  `startTimeMs`/`elapsedSeconds`, which existed only to feed the SpO2 sine
  placeholder and had no other use.
- `activity_main.xml`: removed the SpO2 column (`spo2Text` +
  `spo2StatusText`) entirely; the HR column is now a single centered block.
- `strings.xml`: removed all `spo2_format`/`spo2_placeholder_default`/
  `spo2_status_placeholder` strings. One new string remains,
  `spo2_omitted_note` ("SpO2 intentionally omitted — no validated
  calibration"), shown as a small grey note under the HR reading -- this is
  the only SpO2-related text left anywhere in the app, and it exists only to
  explain the absence, not to display a value.
- Reasoning is tied to `matlab/docs/SpO2_Final_Report_Section.md`
  conceptually (referenced in code comments and the README), whose own
  standing decision is **"not approved for Android display... no validated
  calibration exists that would justify shipping it."** Not duplicated here.

## Action 3 — `onResume` permission re-check — ✅ Done

`MainActivity` previously checked camera permission only in `onCreate`. Now:

- Added `permissionGrantedLastKnown: Boolean`, updated at `onCreate` and by
  the permission-request callback.
- Added `override fun onResume()`, which re-checks `hasCameraPermission()`
  every resume and compares against `permissionGrantedLastKnown`:
  - **Denied → granted while backgrounded** (e.g. user leaves the app,
    grants camera access via system Settings, returns): now calls
    `startCamera()` on resume instead of staying stuck on the denied screen.
  - **Granted → revoked while backgrounded** (the reverse case, not
    originally asked for but the same gap in the other direction): now
    unbinds the camera and shows the denied screen instead of continuing to
    run against a permission that's actually gone.
  - No-ops on the very first resume right after `onCreate` and on every
    resume where nothing changed (compares state, doesn't unconditionally
    act every resume) -- avoids redundant camera rebinds.
- Does **not** add a deep link to system Settings for the Android
  "don't ask again" (`USER_FIXED`) case -- that specific sub-case (flagged
  separately in the README) is unchanged; this fix is scoped to the
  re-check gap that was actually asked for.
- Verified via `./gradlew assembleDebug` (compiles clean) -- on-device
  exercise of the actual resume/Settings round-trip is covered qualitatively
  by watching for zero crashes during the Action 4 stability run below, not
  a separate dedicated test.

## Action 4 — Real stability run (15+ minutes, real pipeline)

**Status: NOT YET RUN.** No physical Android device is currently connected
(`adb devices` returns an empty list from this machine). This is the one
action that requires the physical Samsung Galaxy A35 (or equivalent) used
for all prior on-device verification in `../README.md`.

**This section will be filled in with real logcat/pidof output once a
device is connected and the run is executed** -- protocol below, same
discipline as every prior on-device verification in this project: no
fabricated numbers, report whatever the device actually shows.

### Protocol (to run)

1. Connect device via USB, confirm with `adb devices`.
2. `./gradlew assembleDebug`, `adb install -r`, launch via `adb shell am start`.
3. Confirm `pidof com.spandan.app` at start; re-check periodically to confirm
   no restart across the whole run.
4. Start a parallel `adb logcat` capture for the full session duration,
   watching for `AndroidRuntime`/`FATAL` (crashes) and any other
   `Exception`/`ANR`/`tombstone` entries referencing the app's PID (fatal or
   not).
5. Run continuously for **15+ minutes** with a face in frame (longer than
   every prior run in this project, since this is the defense-day
   confidence check).
6. Record: crash count (expected 0), any non-fatal exceptions logged, and
   whether `RealHeartRateEstimator`'s displayed bpm stayed within a
   physiologically plausible range throughout -- flagging (not silently
   dropping) any sustained reading outside ~40-180bpm, as distinct from the
   old placeholder's hard `.coerceIn(60.0, 90.0)` clamp, which is gone now
   that HR is real and unclamped.

### Result

*(pending -- see Status above)*

## Action 5 — `RoiCalculator.kt` TODO check — ✅ Done, real gap found and fixed

**Not stale documentation -- a real mismatch, confirmed by direct comparison:**

| | TOP | BOTTOM | LEFT | RIGHT |
|---|---|---|---|---|
| Android (before, by-eye) | 0.08 | 0.30 | 0.25 | 0.75 |
| MATLAB (`extractROISignals.m` → `computeRegionBBoxes`, default `forehead`) | 0.10 | 0.30 | 0.30 | 0.70 |

MATLAB's `forehead` mode (`clampedBBox(..., xFracLo=0.30, xFracHi=0.70,
yFracLo=0.10, yFracHi=0.30, ...)`) is explicitly documented in
`extractROISignals.m` as the **unchanged, pre-Task-N geometry** -- i.e. the
exact box Segment 6's validated r=0.957 HR result was computed against. The
Android fractions did not match on three of four edges. Fixed by updating
the four constants in `RoiCalculator.kt` to match MATLAB exactly (see
`android/README.md`'s "ROI fraction placeholder" section, marked
superseded). Verified via `./gradlew assembleDebug` (compiles clean) --
this changes ROI geometry only, not filter/FFT logic, so no unit test
coverage exists or was needed for this change specifically.

## Action 6 — Git: `android/` tracked and committed — ✅ Done

- `android/` was **already tracked** (27 files, committed in `f142798`) --
  the briefed "as of last confirmed state, untracked" premise was stale;
  confirmed via `git ls-files android` before assuming otherwise.
- This session's changes (Actions 2/3/5/7) committed on branch
  `defense-readiness-android-fixes` (branched off `main` per this project's
  branch-before-commit convention), commit `0843fb1`.
- `git status --porcelain android/` returns **empty** after the commit --
  nothing app-relevant remains untracked or modified under `android/`.
- **Out of scope, left alone deliberately**: `matlab/docs/`, several
  `matlab/scripts/run_task_*`/`run_vipl_*` files, and
  `matlab/src/{filtering,validation}/*` remain untracked/modified in this
  repo (Tasks L/N/O/P and related MATLAB exploration). Per this session's
  standing decision, none of that is being ported into the app, and this
  action's scope was `android/` specifically -- these MATLAB-side files are
  a separate, pre-existing housekeeping item for whoever owns that side of
  the repo, not folded into this Android commit.

## Action 7 — `android/README.md` updated — ✅ Done

- Marked superseded (not deleted, per this project's existing
  marking-not-deleting convention, e.g. how the original "PLACEHOLDER
  VALUES banner" checklist item was already handled):
  - Top summary paragraph (SpO2 "still fake" → "no UI at all").
  - The `PlaceholderVitalsEstimator.kt` row in the real/placeholder table
    (file deleted).
  - The SpO2 placeholder-chip paragraph.
  - The "ROI fraction placeholder" section heading and body.
  - The `onResume` gap note in the original verification section.
- Added a short, factual paragraph stating Tasks L/N/O/P were investigated
  in MATLAB and deliberately not ported, with the one-line reason
  (regression risk vs. available runway before defense) -- not a lengthy
  justification.
- Added a pointer at the top of the README to this checklist file.

---

## Final checklist

| # | Action | Status |
|---|---|---|
| 1 | Inspect current state, report honestly | ✅ Done -- see findings above, including one correction to the original briefing |
| 2 | Remove SpO2 UI entirely | ✅ Done |
| 3 | `onResume` permission re-check | ✅ Done |
| 4 | Real 15+ minute stability run | ⏳ **Blocked -- no device connected.** Protocol documented above, ready to run the moment a device is attached. |
| 5 | `RoiCalculator.kt` TODO check | ✅ Done -- real gap found and fixed |
| 6 | Git: `android/` tracked/committed | ✅ Done -- was already tracked, this session's changes now committed, `git status` clean under `android/` |
| 7 | `android/README.md` updated | ✅ Done |

**This checklist will be updated in place once Action 4's stability run is
executed against a connected device -- not marked done until it actually
runs.**

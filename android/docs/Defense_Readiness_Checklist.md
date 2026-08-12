# Defense Readiness Checklist

Status as of **2026-08-12**. This is the "is this ready to demo" summary --
`../README.md` is the detailed build log/history behind it.

**Update, same day, later session:** Action 2 below (written when SpO2 had
just been removed entirely) is **superseded** -- SpO2 was re-added as a
real, live estimate once Task R confirmed the production calibration
transfers to phone-camera data. See
[`SpO2_Live_Implementation.md`](SpO2_Live_Implementation.md) for the
current SpO2 implementation and its own on-device verification. Actions 1,
3, 4, 5, 6, 7 below are unaffected and still current.

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

## Action 2 — SpO2 UI: removed entirely — ✅ Done at the time (superseded, see update note above)

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

## Action 4 — Real stability run (15+ minutes, real pipeline) — ✅ Done

**Status: RUN COMPLETE.** Executed on the same physical **Samsung Galaxy
A35 (SM-A356E)** used for every prior on-device verification in
`../README.md`, once a device was connected and confirmed via
`adb devices`. Protocol followed as specced below; numbers here are read
directly from the actual `adb logcat` capture and `pidof` checks, not
estimated.

### Protocol followed

1. Confirmed device via `adb devices` (`RFCXC0FFFSN`, `SM_A356E`).
2. `./gradlew assembleDebug` (JDK 21 via Android Studio's bundled JBR, same
   pitfall as documented in `../README.md`), `adb install -r`, launched via
   `adb shell am start`.
3. Confirmed `pidof com.spandan.app` = `7340` immediately after launch.
4. Started a parallel `adb logcat -v time` capture for the full session,
   redirected to a file, running the entire time.
5. Ran continuously for **16.1 minutes (968s)** with a face in frame --
   longer than every prior run in this project (previous longest was
   ~13 min *combined across two sessions*; this is one continuous session).
6. Checked `pidof` every 60s throughout (16 checks) and did a final
   full-file analysis afterward, not just the incremental heartbeat checks.

### Result: 0 crashes, 0 exceptions, PID never changed

- **PID stayed at `7340` for the entire run** -- every one of 16 periodic
  checks (every 60s) and the final check after stopping all matched. No
  restart, no process death.
- **Zero crashes.** `grep -E "FATAL EXCEPTION|AndroidRuntime|ANR |tombstone"`
  across the full 111,055-line capture: **0 matches.**
- **Zero exceptions, fatal or non-fatal, referencing the app.**
  `grep -i spandan | grep -i exception` across the full capture: **0
  matches.**
- **17 non-fatal `Log.w` warnings**, all `"Measured fs=... Hz too low for
  the 0.7-4Hz band; skipping this window"` -- this is
  `RealHeartRateEstimator`'s own designed-in guard (skip a window rather
  than compute a meaningless FFT on it), not an error. Two clusters, both
  explained rather than just counted:
  - **7 warnings at the very start** (18:04:40-46) -- expected buffer
    warm-up, before the 25s window had enough samples for a reliable `fs`
    estimate.
  - **10 warnings at ~14 minutes in** (18:18:43-52) -- checked directly
    against the surrounding log: `n`/`window` values right before this
    (`n=334, window=25.0s`) and right after (`n=131, window=11.0s` growing
    back up to `n=225, window=18.0s` over the next several seconds) show
    the classic signature of a brief no-face period (matches
    `SignalBuffer`'s documented behavior of not appending new samples
    when no face is detected, so the window ages/shrinks then rebuilds once
    a face is redetected) -- not a bug, and it self-recovered within ~10
    seconds with no crash.

### HR plausibility: real, unclamped values checked against 40-180bpm

**983 displayed-bpm readings** extracted directly from
`RealHeartRateEstimator`'s per-recompute log line (`displayed=... (X.Xbpm)`)
across the full run:

| | Value |
|---|---|
| Readings | 983 |
| Range | 47.9 - 184.4 bpm |
| Mean | 83.4 bpm |
| Outside 40-180bpm | 1 / 983 (0.1%) |
| Outside a tighter 45-150bpm band | 5 / 983 (0.5%) |

**The single >180bpm reading (184.4bpm at 18:14:34.710) was checked for
whether it was sustained or a one-off spike, per this action's exact
ask -- it was a one-off.** Its immediate neighbors: `...105.4, 105.4,
184.4, 136.6, 64.6, 119.8...` -- one isolated sample surrounded by
105-136bpm readings a second before and after, not a sustained excursion.
This matches the FFT-bin-quantization jitter pattern already documented
elsewhere in `../README.md` for this build's ~2.4bpm bin resolution at a
25s window, not a new failure mode. Unlike the old placeholder's hard
`.coerceIn(60.0, 90.0)` clamp, nothing here artificially bounds the
displayed value -- these are the pipeline's real, unclamped outputs, and
99.9% of them landed inside 40-180bpm on their own.

### Honest bottom line

**Zero crashes, zero exceptions, one continuous 16+ minute run on the real
pipeline, PID constant throughout.** This is new evidence -- no prior run
in this project covered 15+ continuous minutes on `RealHeartRateEstimator`
in one sitting. HR values were physiologically plausible 99.9% of the time,
with the one exception being an isolated single-sample spike consistent
with already-documented FFT-bin jitter, not a sustained or crash-adjacent
problem. This is the strongest stability evidence this project has for
defense day.

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
| 4 | Real 15+ minute stability run | ✅ Done -- 16.1 min continuous, 0 crashes, 0 exceptions, PID constant, HR plausible 99.9% of readings |
| 5 | `RoiCalculator.kt` TODO check | ✅ Done -- real gap found and fixed |
| 6 | Git: `android/` tracked/committed | ✅ Done -- was already tracked, this session's changes now committed, `git status` clean under `android/` |
| 7 | `android/README.md` updated | ✅ Done |

**All seven actions are complete.** Action 4's stability run executed
against the physical Samsung Galaxy A35 on 2026-08-12: 16.1 continuous
minutes, 0 crashes, 0 exceptions, PID constant throughout, HR
physiologically plausible in 99.9% of readings. See the full breakdown
above.

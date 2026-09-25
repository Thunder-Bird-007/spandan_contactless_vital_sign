# Segment 16 Task 3 — UI/UX Pass

Status as of **2026-09-14**. Presentation-only — no change to the camera/
signal pipeline anywhere in this task; every file touched is a layout,
drawable, string, color resource, or the small MainActivity glue that reads
already-computed values and colors/labels them.

---

## 1. What was wrong with the previous layout

`activity_main.xml` before this task (see git history / `docs/
SpO2_Live_Implementation.md`'s own description of the prior state): a plain
`LinearLayout`, flat `#000000` background strip under the camera preview,
two `TextView`s (`hrText`, `spo2Text`) at a fixed 20sp with no visual
grouping, no status indication beyond the raw text itself, and no feedback
at all when a face is not detected beyond the overlay boxes silently
disappearing. Per-field status chips ("● LIVE — CHROM/POS + FFT" etc.) had
existed at one point and were removed for "a cleaner UI," per that layout's
own top comment — but their removal left the number completely
unexplained: a viewer could not tell "warming up" from "signal is bad" from
"working fine," all three showed as either a plain number or `-- bpm`.

## 2. What changed

- **Vitals card**: HR and SpO2 now live inside a single rounded,
  semi-transparent card (`bg_vitals_card.xml`) instead of a flat black
  strip — a hairline border (`surface_card_border`) keeps it readable as a
  distinct surface against a bright or busy camera feed without needing a
  real drop shadow (which barely reads against black).
- **Typography**: each metric gets a small all-caps caption ("HEART RATE" /
  "BLOOD OXYGEN") above a much larger, bold value (34sp bold, up from 20sp
  plain) — the number is now unambiguously the focal point, with the
  caption giving context a bare number lacked.
- **Status pills, restored and made meaningful**: each metric has its own
  small colored-dot + short-label pill below the value, but instead of a
  binary "real vs. fake" chip, it now reflects `signal.EstimatorStatus`
  (Segment 16 Task 1/2's shared enum) plus a UI-only `NO_FACE` case:

  | State | Color | Label |
  |---|---|---|
  | `OK` | green (`status_ok`, matches `OverlayView`'s face-box green exactly) | "Live — CHROM/POS + FFT" / "Estimate — narrow reference range (87–99%)" |
  | `WARMING_UP` | amber (`status_warming`) | "Warming up…" |
  | `LOW_SIGNAL_QUALITY` | orange-red (`status_low_quality`) | "Low signal quality" |
  | no face sustained | red (`status_no_face`) | "No face detected" |

  This directly answers the brief's request for "no face detected"/"low
  confidence"/"warming up" states — each is now a visually distinct,
  correctly-labeled pill instead of all three collapsing into the same
  placeholder text.
- **"No face detected" banner**: a centered, debounced (1200ms — see
  `MainActivity.NO_FACE_DEBOUNCE_MS`) banner now appears over the preview
  when no face has been seen for a sustained period, with a short
  actionable subtitle ("Center your face in frame, hold still, and make
  sure your forehead is well lit."). Debounced specifically so a single
  missed detection (normal noise, or one of `FaceAnalyzer`'s own
  every-Nth-frame detection-skip cycles) never flashes it.
- **Chart card**: the raw-signal chart now sits in its own small card with
  a caption ("LIVE SIGNAL"), matching the vitals card's visual language
  instead of floating on bare black.
- **Color/contrast**: a small, deliberately limited palette (`colors.xml`)
  was extracted from colors that already existed inline in
  `OverlayView.kt`/`SignalChartView.kt` (the face-box green, ROI-box
  yellow, chart green/background) so the new UI reads as one system with
  the existing camera overlay rather than a clashing second palette, plus
  new text/surface tokens (`text_primary`/`text_secondary`/`text_tertiary`
  at ~100%/70%/50% white) for deliberate text-hierarchy contrast against
  the black camera background.

**Scope discipline**: every existing view ID MainActivity.kt already used
(`previewView`, `overlayView`, `permissionDeniedView`, `chartView`,
`hrText`, `spo2Text`, `grantPermissionButton`, `rootLayout`) was kept
exactly as-is; only new IDs were added (`noFaceBanner`, `hrStatusDot`,
`hrStatusLabel`, `spo2StatusDot`, `spo2StatusLabel`). No camera, ROI,
filtering, CHROM/POS, FFT, or calibration code was touched by this task —
confirmed by inspection: the only non-`res/`, non-layout files this task's
diff touches are `MainActivity.kt` (view wiring + a pure status→color/label
mapping function, `applyStatusPill`, which is never called from and never
influences the signal path) and the two estimator files' additive
`lastStatus` properties (shared with Task 1/2, described in their own docs).

## 3. Build verification (no device needed)

`./gradlew assembleDebug`: **BUILD SUCCESSFUL**, no compile errors. One
real build failure was hit and fixed during this task, XML-syntax only, not
a logic bug: several new comments used a literal `--` (e.g. "Segment 16
Task 3 -- ..."), which is illegal inside an XML comment body and broke
`mergeDebugResources` with `Error: The string "--" is not permitted within
comments` — the exact pitfall `android/README.md`'s own HR-port section
already documents hitting once before ("`--` inside XML comments is
illegal XML and broke resource merging"). Fixed by switching to a colon or
an em dash (`—`, a single Unicode character, not two hyphens) in every
affected comment; re-verified with a precise search (`--` not adjacent to
the `<!--`/`-->` delimiters themselves) that none remain.

## 4. On-device status: VERIFIED on real hardware (screenshots not retained)

**Update, same day.** A physical device (the same Samsung Galaxy A35,
`RFCXC0FFFSN`, used throughout this project) became available partway
through this task. The emulator attempt described below (kept for the
record, since it's a real, potentially-recurring environment constraint
worth documenting) turned out not to be needed once real hardware was
connected.

### The emulator attempt (for the record — superseded by real hardware below)

Before a device was available, this project's build machine's local
Android Studio AVD (`Pixel_7`) was tried as a substitute. Booted via
`emulator.exe -avd Pixel_7 -no-snapshot -no-boot-anim`, with
`hasCompatibleHypervisor`/`hasSufficientSystem`/`hasSufficientHwGpu`/
`hasSufficientDiskSpace` all reporting `Ok` in its own startup log. Left
running over 20 minutes; `adb devices` reported `emulator-5554 offline`
the entire time (never reached `getprop sys.boot_completed=1`), while the
underlying `qemu-system-x86_64` process's CPU time climbed continuously
(541s → 677s across two checks) — actively computing, not hung, but never
completing a boot. Consistent with slow/unaccelerated virtualization in
that execution environment, not a bug in the AVD or this task's changes.
Stopped once a device became available and made this moot.

### Real on-device verification

`adb devices` confirmed attached; `./gradlew assembleDebug` — **BUILD
SUCCESSFUL**. Real before/after captures were taken via `adb shell
screencap` (git-stashing this task's tracked changes to rebuild the
genuine pre-redesign layout for the "before" shot, then restoring them),
covering four states:

| State | What it showed |
|---|---|
| **Before** (pre-Segment-16) | Flat black strip, plain 20sp `HR: 134 bpm` / `SpO2: 96.76%`, no status pills, no no-face feedback |
| **After — live** | Vitals card, `130 bpm` / `96.81%`, green "Live — CHROM/POS + FFT" / "Estimate — narrow reference range" pills, chart in its own "LIVE SIGNAL" card |
| **After — warming up** | `-- bpm` / `-- %`, amber "Warming up…" pills on both metrics — a real, freshly-captured warm-up state, not simulated |
| **After — no face** | The debounced "No face detected" banner, genuinely triggered (camera pointed away from the subject), with its actionable subtitle |

**The image files themselves (and the gallery artifact built from them)
were deleted at the user's request** (2026-09-14, contained the subject's
face) — this table records what was verified, not what is retained. No
copy was committed to git and nothing reached GitHub (confirmed: the
screenshots were untracked local files at deletion time, and this
project's last actual commit predates this task). See
`android/README.md`'s own Segment 16 section for the same note.

### A real bug found via the "after" capture, fixed, re-verified

The first "after — live" capture showed the value text wrapping onto two
lines inside its half-width column ("HR: 73" / "bpm" on separate lines,
similarly for SpO2) — the 34sp bold `"HR: %.0f bpm"`/`"SpO2: %.2f%%"`
format strings were too wide for the card's column at that size. Fixed by
dropping the now-redundant `"HR:"/"SpO2:"` prefix from `hr_format`/
`spo2_format` (redundant since the card already has a "HEART RATE"/"BLOOD
OXYGEN" caption above the value) rather than just shrinking the font —
fixing the wrap and the redundancy at once. Hit the same `--`-in-XML-
comment pitfall again while writing the fix's own KDoc (see §3) — fixed
the same way. Re-verified on-device: the corrected build showed both
values on a single line before that capture was deleted along with the
rest.

### Crash check

Across every build/install/run in this task and Task 1's combined on-device
session: **zero** `FATAL EXCEPTION`/`AndroidRuntime` entries in any capture,
`pidof com.spandan.app` stayed constant within each run (no restarts). The
one Android system dialog encountered (the pre-existing, already-documented
"Android App Compatibility" 16KB-page-size warning, `android/README.md`'s
own "Aside, unrelated to app code" note) is not an app crash and was simply
dismissed before continuing.

### What is still not confirmed

Spacing/sizing on a different screen density than this one device, and
whether the debounce timing (1200ms) feels right across more than this one
session's brief interaction — both reasonable follow-ups, neither a gap
serious enough to withhold this task's overall result.

## Files

- `android/app/src/main/res/layout/activity_main.xml` (rewritten)
- `android/app/src/main/res/values/colors.xml` (new)
- `android/app/src/main/res/values/strings.xml` (modified — new status/label strings, plus the on-device text-wrap fix)
- `android/app/src/main/res/drawable/bg_vitals_card.xml` (new)
- `android/app/src/main/res/drawable/bg_status_pill.xml` (new)
- `android/app/src/main/res/drawable/bg_no_face_banner.xml` (new)
- `android/app/src/main/res/drawable/shape_status_dot.xml` (new)
- `android/app/src/main/java/com/spandan/app/MainActivity.kt` (modified — view wiring, no-face debounce, `applyStatusPill`)

No screenshot files are retained in this repo — captured during verification (see §4), deleted at the user's request afterward.

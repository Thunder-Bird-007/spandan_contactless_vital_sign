package com.spandan.app.signal

/**
 * Segment 19 (Branch 2 morphology port) -- real port of
 * `matlab/src/morphology/bandpassMorphology.m` (read directly from source
 * before writing this). A WIDER bandpass than [BandpassFilter]'s own
 * 0.7-4Hz HR-tuned band: the dicrotic notch is carried by the 3rd-5th
 * cardiac harmonics, not the fundamental, so a 4Hz cutoff throws away the
 * harmonic content the notch needs, by construction, at every HR this
 * project's cohorts actually sit at.
 *
 * Reuses [BandpassFilter.designButterworthBandpass] and [BandpassFilter.filtfilt]
 * directly (both already `public fun` on that object) rather than
 * duplicating the Butterworth-design/filtfilt machinery -- [BandpassFilter.kt]
 * itself is on this project's "do not touch" list (Branch 1, already
 * measured/validated); this file only CALLS its already-public methods with
 * different order/cutoff arguments, it does not modify them.
 *
 * MATLAB source, exact parameters confirmed:
 *   bandpassMorphology.m: filterOrder = 3 (one order higher than
 *     bandpassClean.m's 2); 'wide' = 0.5-8.0Hz (DEFAULT, matches Branch 2's
 *     production default); 'mid' = 0.6-6.0Hz (validated non-default
 *     alternative, useful when 'wide' isn't admissible under Nyquist --
 *     see [pick] below); 'legacy' = 0.7-4.0Hz is NOT ported here since it
 *     only exists in MATLAB for a batch-ablation comparison, never a live
 *     pipeline path.
 */
object MorphologyBandpassFilter {

    enum class BandMode(val lowHz: Double, val highHz: Double) {
        WIDE(0.5, 8.0),
        MID(0.6, 6.0)
    }

    const val ORDER = 3

    data class Result(val filtered: DoubleArray, val bandUsed: BandMode)

    /** Butterworth order-3 bandpass + filtfilt at [mode]'s cutoffs, against a
     *  RUNTIME-MEASURED [fs] (never hardcoded, same discipline as [BandpassFilter]).
     *  Throws [IllegalArgumentException] if [mode]'s high cutoff is at or
     *  above the Nyquist frequency for [fs] -- matching
     *  `bandpassMorphology.m`'s own `error('bandpassMorphology:cutoffAboveNyquist', ...)`
     *  guard exactly (a hard error there since it runs on offline batch data;
     *  a live caller here should check [pick] or [isAdmissible] first rather
     *  than relying on this exception for control flow). */
    fun apply(sigDetrended: DoubleArray, fs: Double, mode: BandMode): Result {
        require(isAdmissible(fs, mode)) {
            "highCutoffHz (${mode.highHz}) for bandMode $mode is at or above the Nyquist frequency (${fs / 2.0}) for fs=$fs."
        }
        val (b, a) = BandpassFilter.designButterworthBandpass(ORDER, mode.lowHz, mode.highHz, fs)
        return Result(BandpassFilter.filtfilt(b, a, sigDetrended), mode)
    }

    /** True if [mode]'s high cutoff is strictly below Nyquist for [fs] --
     *  same condition `bandpassMorphology.m` checks before erroring. */
    fun isAdmissible(fs: Double, mode: BandMode): Boolean = mode.highHz < fs / 2.0

    /**
     * Segment 18/19 interaction, stated plainly per the task brief: Branch
     * 2's wide 0.5-8Hz band needs fs comfortably above 16Hz to stay
     * meaningful under Nyquist (matching `matlab/docs/
     * Segment10_Task3_Tier0_Diagnostics.md`'s own finding that a real ~16fps
     * VIPL subject leaves 'wide' with a razor-thin admissibility margin).
     * This app's measured on-device throughput (13.44-21.40fps depending on
     * the frame-skip optimization, see `android/docs/
     * Segment7_Task_G_Throughput_Profiling.md`) sits AT or BELOW that
     * margin, not comfortably above it -- so a live caller cannot assume
     * 'wide' is always admissible the way every MATLAB batch script (which
     * only ever processes fixed-fps UBFC/VIPL clips well above 16fps) could.
     *
     * Picks the widest ('wide' preferred, then 'mid') admissible mode for
     * [fs], or null if fs is too low for even 'mid' -- callers ([MorphologyWaveformEstimator])
     * should treat null as "skip this window" (fail soft), not throw, since
     * this runs live on uncontrolled camera data.
     */
    fun pick(fs: Double): BandMode? = when {
        isAdmissible(fs, BandMode.WIDE) -> BandMode.WIDE
        isAdmissible(fs, BandMode.MID) -> BandMode.MID
        else -> null
    }
}

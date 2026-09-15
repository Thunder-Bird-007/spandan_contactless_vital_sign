package com.spandan.app.signal

import org.jtransforms.fft.DoubleFFT_1D

/**
 * Segment 19 (Branch 2 morphology port) -- real port of
 * `matlab/src/morphology/adaptiveHarmonicFilter.m` (read directly from
 * source before writing this): harmonic-comb filter (ABPF, Moco/Stuijk/de
 * Haan, Sci Rep 8:8501, 2018). Keeps only narrow (3-bin) windows around the
 * cardiac fundamental and each of its harmonics, zeroes everything else,
 * inverse-FFTs back -- rejects inter-harmonic noise a flat bandpass
 * ([MorphologyBandpassFilter]) would pass through.
 *
 * FFT masking is built directly in a 0-based array (JTransforms'
 * `complexForward`/`complexInverse` convention), hand-translated from the
 * MATLAB source's 1-based bin indexing -- verified against a synthetic
 * multi-harmonic signal in [AdaptiveHarmonicFilterTest] before trusting it
 * on real camera data, same discipline as every numeric port here.
 */
object AdaptiveHarmonicFilter {

    data class Result(val filtered: DoubleArray, val f0Hz: Double, val harmonicsUsedHz: List<Double>)

    /**
     * @param numHarmonics how many harmonics (h=1..numHarmonics) to keep. 6,
     *   matching the MATLAB default, unless the caller passes otherwise.
     * @param f0HzOverride if non-null, skips the internal
     *   [HeartRateFft.estimateBpm] call and uses this as f0 -- used by
     *   [MorphologyWaveformEstimator] to force all three R/G/B channels onto
     *   the SAME shared f0 (estimated once from the combined wide-band CHROM
     *   pulse), matching `pipeline/estimateVitalsAndMorphology.m`'s own
     *   design exactly (see that file's "NOTE on the shared f0" comment).
     * @throws IllegalStateException if [f0HzOverride] is null and no FFT bin
     *   falls inside [HeartRateFft]'s 0.7-4Hz band (mirrors
     *   `fftHeartRate.m`'s own hard error; a live caller here should always
     *   supply [f0HzOverride] from an already-validated shared estimate, per
     *   the design above, so this path should not normally be hit).
     */
    fun apply(sigDetrended: DoubleArray, frameRate: Double, numHarmonics: Int = 6, f0HzOverride: Double? = null): Result {
        val sigRow = sigDetrended
        val n = sigRow.size

        val f0Hz = f0HzOverride ?: (
            HeartRateFft.estimateBpm(sigRow, frameRate)?.bpm?.div(60.0)
                ?: error("AdaptiveHarmonicFilter: no FFT bin fell inside the 0.7-4Hz band; caller must supply f0HzOverride")
            )

        val freqResolution = frameRate / n
        val nyquistBinIdx0 = n / 2 // 0-based index of the Nyquist (or highest positive-freq) bin

        val complexData = DoubleArray(2 * n)
        for (i in 0 until n) complexData[2 * i] = sigRow[i]
        DoubleFFT_1D(n.toLong()).complexForward(complexData)

        val mask = BooleanArray(n)
        val harmonicsUsedHz = mutableListOf<Double>()

        for (h in 1..numHarmonics) {
            val harmonicFreqHz = h * f0Hz
            val centerBinIdx0 = Math.round(harmonicFreqHz / freqResolution).toInt()
            if (centerBinIdx0 > nyquistBinIdx0) continue // this harmonic and all higher ones are above Nyquist
            harmonicsUsedHz.add(harmonicFreqHz)

            for (offset in -1..1) {
                val binIdx0 = centerBinIdx0 + offset
                if (binIdx0 < 1 || binIdx0 > nyquistBinIdx0) continue // skip DC (bin 0) and anything past Nyquist
                mask[binIdx0] = true
                val mirror0 = n - binIdx0
                if (mirror0 in 0 until n) mask[mirror0] = true
            }
        }

        val filteredComplex = DoubleArray(2 * n)
        for (k in 0 until n) {
            if (mask[k]) {
                filteredComplex[2 * k] = complexData[2 * k]
                filteredComplex[2 * k + 1] = complexData[2 * k + 1]
            }
        }
        DoubleFFT_1D(n.toLong()).complexInverse(filteredComplex, true)

        val filtered = DoubleArray(n) { i -> filteredComplex[2 * i] } // real part -- mask is symmetric by construction
        return Result(filtered, f0Hz, harmonicsUsedHz)
    }
}

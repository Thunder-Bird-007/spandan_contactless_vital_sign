package com.spandan.app.signal

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HarmonicFilterConfidenceGateTest {

    private fun sig(v: Double) = doubleArrayOf(v)

    @Test
    fun keepsPrimaryWhenItClearsTheBar() {
        val primary = HarmonicFilterConfidenceGate.Candidate(sig(1.0), notchConfidence = 0.5, methodLabel = "adaptiveHarmonic")
        val fallback = HarmonicFilterConfidenceGate.Candidate(sig(2.0), notchConfidence = 0.9, methodLabel = "gaussian015")

        val result = HarmonicFilterConfidenceGate.select(primary, listOf(fallback))

        assertFalse(result.wasSubstituted)
        assertEquals("adaptiveHarmonic", result.selectedMethodLabel)
        assertEquals(0.5, result.selectedNotchConfidence, 1e-9)
    }

    @Test
    fun substitutesFallbackWhenPrimaryFailsTheBar() {
        val primary = HarmonicFilterConfidenceGate.Candidate(sig(1.0), notchConfidence = 0.1, methodLabel = "adaptiveHarmonic")
        val fallback = HarmonicFilterConfidenceGate.Candidate(sig(2.0), notchConfidence = 0.4, methodLabel = "gaussian015")

        val result = HarmonicFilterConfidenceGate.select(primary, listOf(fallback))

        assertTrue(result.wasSubstituted)
        assertEquals("gaussian015", result.selectedMethodLabel)
        assertEquals(0.4, result.selectedNotchConfidence, 1e-9)
    }

    @Test
    fun exactlyAtTheBarDoesNotCountAsPassing() {
        // primaryNotchConfidence > threshold, strictly -- matching
        // harmonicFilterConfidenceGate.m's own `primaryNotchConfidence > confidenceThreshold`.
        val primary = HarmonicFilterConfidenceGate.Candidate(sig(1.0), notchConfidence = 0.3, methodLabel = "adaptiveHarmonic")
        val fallback = HarmonicFilterConfidenceGate.Candidate(sig(2.0), notchConfidence = 0.35, methodLabel = "gaussian015")

        val result = HarmonicFilterConfidenceGate.select(primary, listOf(fallback), confidenceThreshold = 0.3)

        assertTrue("exactly at the bar should NOT pass (needs strictly >)", result.wasSubstituted)
    }

    @Test
    fun naNPrimaryConfidenceAlwaysSubstitutes() {
        val primary = HarmonicFilterConfidenceGate.Candidate(sig(1.0), notchConfidence = Double.NaN, methodLabel = "adaptiveHarmonic")
        val fallback = HarmonicFilterConfidenceGate.Candidate(sig(2.0), notchConfidence = 0.1, methodLabel = "gaussian015")

        val result = HarmonicFilterConfidenceGate.select(primary, listOf(fallback))
        assertTrue(result.wasSubstituted)
    }
}

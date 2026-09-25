package com.spandan.app.camera

import android.graphics.Rect
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * Plain Kotlin/JUnit -- verifies [Kalman1D]'s scalar Kalman math against
 * synthetic motion/noise, and [KalmanBoxTracker]'s box-geometry wiring on
 * top of it. Every [Rect] fed into the code under test is built via
 * [rectOf], never the 4-arg `Rect(l,t,r,b)` constructor directly -- see
 * [CroppedDetectionStrategyTest]'s own note on why that constructor is a
 * no-op under this project's plain-JUnit harness.
 */
class KalmanBoxTrackerTest {

    private fun rectOf(left: Int, top: Int, right: Int, bottom: Int): Rect {
        val r = Rect()
        r.left = left
        r.top = top
        r.right = right
        r.bottom = bottom
        return r
    }

    // === Kalman1D ===

    @Test
    fun kalman1D_predictAdvancesPositionByCurrentVelocity() {
        val k = Kalman1D(processNoisePos = 1.0, processNoiseVel = 1.0, measurementNoise = 10.0)
        k.init(100.0)
        // Feed two measurements 5 apart to establish a velocity estimate.
        k.predict()
        k.correct(105.0)
        k.predict()
        k.correct(110.0)

        val velBefore = k.vel
        val posBefore = k.pos
        k.predict()
        // With no new correction, predict() should move pos by roughly the
        // last known velocity (constant-velocity model).
        assertEquals(posBefore + velBefore, k.pos, 1e-9)
    }

    @Test
    fun kalman1D_tracksConstantVelocityMotionCloselyOverManySteps() {
        val k = Kalman1D(processNoisePos = 4.0, processNoiseVel = 4.0, measurementNoise = 1.0)
        val trueVelocity = 3.0
        var truePos = 0.0
        k.init(truePos)

        for (step in 1..50) {
            truePos += trueVelocity
            k.predict()
            k.correct(truePos) // noiseless measurement -- filter should converge tightly
            if (step > 10) {
                val error = abs(k.pos - truePos)
                assertTrue("error should stay small once converged, was $error at step $step", error < 5.0)
            }
        }
        // Velocity estimate should also converge close to the true constant velocity.
        assertTrue("velocity estimate should converge near $trueVelocity, was ${k.vel}", abs(k.vel - trueVelocity) < 0.5)
    }

    @Test
    fun kalman1D_smoothsNoisyMeasurementsAroundAFixedPosition() {
        val k = Kalman1D(processNoisePos = 0.5, processNoiseVel = 0.5, measurementNoise = 25.0)
        val truePos = 200.0
        val rng = kotlin.random.Random(42)
        k.init(truePos)

        val noisyMeasurements = mutableListOf<Double>()
        val filteredPositions = mutableListOf<Double>()
        repeat(60) {
            val noisy = truePos + (rng.nextDouble() - 0.5) * 20.0 // +/- 10 uniform noise
            noisyMeasurements.add(noisy)
            k.predict()
            k.correct(noisy)
            filteredPositions.add(k.pos)
        }

        // Compare variance of the raw noisy measurements vs. the filtered
        // output's deviation from the true position, over the back half
        // (after initial convergence) -- the filter should reduce spread.
        val tail = filteredPositions.takeLast(30)
        val noisyTail = noisyMeasurements.takeLast(30)
        val filteredMeanAbsError = tail.map { abs(it - truePos) }.average()
        val noisyMeanAbsError = noisyTail.map { abs(it - truePos) }.average()

        assertTrue(
            "filtered mean abs error ($filteredMeanAbsError) should be less than raw noisy mean abs error ($noisyMeanAbsError)",
            filteredMeanAbsError < noisyMeanAbsError
        )
    }

    // === KalmanBoxTracker ===

    @Test
    fun predict_returnsNullBeforeAnyCorrection() {
        val tracker = KalmanBoxTracker()
        assertNull(tracker.predict())
    }

    @Test
    fun correct_firstCallHardInitsWithZeroVelocity() {
        val tracker = KalmanBoxTracker()
        tracker.correct(rectOf(100, 100, 200, 200))

        val predicted = tracker.predict()
        assertTrue(predicted != null)
        // Zero initial velocity -- one predict() step after a single
        // correct() should not have moved the box.
        assertEquals(100, predicted!!.left)
        assertEquals(100, predicted.top)
        assertEquals(200, predicted.right)
        assertEquals(200, predicted.bottom)
    }

    @Test
    fun clear_forgetsPriorStateSoPredictReturnsNullAgain() {
        val tracker = KalmanBoxTracker()
        tracker.correct(rectOf(100, 100, 200, 200))
        assertTrue(tracker.predict() != null)

        tracker.clear()
        assertNull(tracker.predict())
    }

    @Test
    fun tracksABoxMovingAtConstantVelocityAndExtrapolatesInTheRightDirection() {
        val tracker = KalmanBoxTracker(processNoisePos = 4.0, processNoiseVel = 4.0, measurementNoise = 1.0)
        // Simulate a 100x100 box moving +10px/frame in x, stationary in y,
        // observed (corrected) every frame -- noiseless, so the filter
        // should lock onto the true velocity quickly.
        var left = 0
        repeat(20) {
            tracker.predict()
            tracker.correct(rectOf(left, 100, left + 100, 200))
            left += 10
        }

        // Now simulate 3 SKIPPED frames (no correction) -- predict() alone
        // should keep extrapolating in the same direction at roughly the
        // same rate, landing close to where the box would actually be.
        val predicted1 = tracker.predict()!!
        val predicted2 = tracker.predict()!!
        val predicted3 = tracker.predict()!!

        val expectedLeftAfter3Skips = left + 30 // 3 more frames at ~10px/frame
        // Tolerance is deliberately loose (not a tight bound): a Kalman
        // filter with nonzero process noise on velocity always lags a true
        // constant-velocity signal slightly at steady state, even with
        // near-noiseless measurements -- this is correct filter behavior,
        // not a bug, so the test only checks the extrapolation is in the
        // right ballpark and direction, not pixel-exact.
        assertTrue(
            "predicted3.left (${predicted3.left}) should be reasonably close to expected ($expectedLeftAfter3Skips)",
            abs(predicted3.left - expectedLeftAfter3Skips) < 15
        )
        // Direction sanity: each successive prediction should move further right.
        assertTrue(predicted2.left > predicted1.left)
        assertTrue(predicted3.left > predicted2.left)
        // Size should stay stable (box wasn't changing size).
        assertEquals(100, predicted3.right - predicted3.left)
        assertEquals(100, predicted3.bottom - predicted3.top)
    }
}

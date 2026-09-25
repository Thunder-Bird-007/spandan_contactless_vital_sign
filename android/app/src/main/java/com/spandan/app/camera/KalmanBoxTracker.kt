package com.spandan.app.camera

import android.graphics.Rect

/**
 * [Segment 29] Camera-throughput candidate #3, a different risk class from
 * both [OpticalFlowFaceTracker] and [CroppedDetectionStrategy]: a constant-
 * velocity Kalman filter over the face box's own geometry (center x/y,
 * width, height), extrapolated on skipped-detection frames and corrected
 * whenever a real ML Kit detection arrives. Unlike [OpticalFlowFaceTracker]
 * (SAD block matching on downsampled luma pixels) it never reads pixel
 * content at all -- only the sequence of previously observed/predicted box
 * geometries -- so it cannot inherit the skin-texture/lighting drift failure
 * mode `matlab/docs/Segment7_Task_D_Landmark_ROI.md` documented for a
 * KLT-tracked ROI (that finding is specifically about pixel-content
 * tracking, which this class deliberately avoids). Standard SORT-style
 * technique (a constant-velocity Kalman filter per box coordinate is the
 * textbook multi-object-tracking building block), applied here to a single
 * face rather than a multi-object association problem.
 *
 * Decomposed into four independent 1D constant-velocity filters ([Kalman1D],
 * one each for center-x, center-y, width, height) rather than one coupled
 * 8-state filter -- mathematically equivalent under the diagonal-process-
 * noise assumption used here (no modeled cross-correlation between, say,
 * horizontal motion and box width), and far simpler to implement/verify
 * without a general matrix library.
 *
 * Same "advance every frame, correct only on a real detection" discipline a
 * textbook Kalman filter expects: [predict] must be called once per frame
 * (skipped or real) to keep the internal time base at a consistent dt=1 per
 * call; [correct] is called immediately after [predict] on frames with a
 * real detection, fusing the observation into the just-advanced state.
 *
 * HONEST STATUS: the noise parameters below ([Kalman1D]'s defaults) are
 * reasonable starting guesses (pixel-scale process/measurement noise for a
 * ~640x480 frame), NOT fit to any measured ML Kit detection jitter -- no
 * ground-truth face-position data was available this session to fit them
 * properly. Unit-tested against synthetic linear motion and synthetic
 * measurement noise only; not yet validated against real ML Kit detection
 * sequences for whether it actually reduces ROI positional error relative
 * to the plain frozen-box default, only that it runs correctly.
 */
class KalmanBoxTracker(
    processNoisePos: Double = 4.0,
    processNoiseVel: Double = 4.0,
    measurementNoise: Double = 25.0
) {
    private val cx = Kalman1D(processNoisePos, processNoiseVel, measurementNoise)
    private val cy = Kalman1D(processNoisePos, processNoiseVel, measurementNoise)
    private val w = Kalman1D(processNoisePos, processNoiseVel, measurementNoise)
    private val h = Kalman1D(processNoisePos, processNoiseVel, measurementNoise)
    private var initialized = false

    /** Discards all filter state (e.g. after a NoFace frame) so the next
     *  real detection starts a clean track rather than extrapolating from a
     *  stale, possibly now-irrelevant position/velocity estimate. */
    fun clear() {
        initialized = false
    }

    /**
     * Call ONCE PER FRAME on every skipped-detection frame. Advances the
     * filter's internal state by one frame (dt=1) and returns the
     * extrapolated box, or null if no detection has ever been observed yet.
     */
    fun predict(): Rect? {
        if (!initialized) return null
        cx.predict()
        cy.predict()
        w.predict()
        h.predict()
        return boxFromCenterSize(cx.pos, cy.pos, w.pos, h.pos)
    }

    /**
     * Call on every frame with a real ML Kit detection, immediately after
     * [predict] (whose return value the caller does not need to use --
     * real-detection frames keep emitting the raw ML Kit box unchanged,
     * same as [OpticalFlowFaceTracker]'s own convention; this call only
     * keeps the filter's internal state, especially its velocity estimate,
     * correctly synced to reality). First call after construction or
     * [clear] performs a hard reset instead of a Kalman update, since there
     * is no prior state yet to fuse against.
     */
    fun correct(box: Rect) {
        val observedCx = (box.left + box.right) / 2.0
        val observedCy = (box.top + box.bottom) / 2.0
        val observedW = (box.right - box.left).toDouble()
        val observedH = (box.bottom - box.top).toDouble()

        if (!initialized) {
            cx.init(observedCx)
            cy.init(observedCy)
            w.init(observedW)
            h.init(observedH)
            initialized = true
            return
        }

        cx.correct(observedCx)
        cy.correct(observedCy)
        w.correct(observedW)
        h.correct(observedH)
    }

    private fun boxFromCenterSize(centerX: Double, centerY: Double, width: Double, height: Double): Rect {
        val halfW = width / 2.0
        val halfH = height / 2.0
        val r = Rect()
        r.left = (centerX - halfW).toInt()
        r.top = (centerY - halfH).toInt()
        r.right = (centerX + halfW).toInt()
        r.bottom = (centerY + halfH).toInt()
        return r
    }
}

/**
 * Textbook 2-state (position, velocity) discrete Kalman filter, dt=1 per
 * [predict] call. Diagonal-noise simplification of the general n-D case --
 * see [KalmanBoxTracker]'s own KDoc for why four of these (one per box
 * coordinate) are used instead of one coupled 8-state filter.
 */
class Kalman1D(
    private val processNoisePos: Double,
    private val processNoiseVel: Double,
    private val measurementNoise: Double
) {
    var pos: Double = 0.0
        private set
    var vel: Double = 0.0
        private set

    // Covariance P = [[pPosPos, pPosVel], [pPosVel, pVelVel]] (symmetric).
    private var pPosPos = 0.0
    private var pPosVel = 0.0
    private var pVelVel = 0.0

    /** Hard reset to an observed position, zero velocity, high initial
     *  uncertainty (the filter has no basis yet to trust this estimate over
     *  the next real observation). */
    fun init(observedPos: Double) {
        pos = observedPos
        vel = 0.0
        pPosPos = INITIAL_UNCERTAINTY
        pPosVel = 0.0
        pVelVel = INITIAL_UNCERTAINTY
    }

    /** State transition (F = [[1,1],[0,1]], dt=1) plus additive process
     *  noise Q = diag(processNoisePos, processNoiseVel): P' = F P F^T + Q. */
    fun predict() {
        pos += vel
        // vel unchanged (constant-velocity model)

        val newPPosPos = pPosPos + 2 * pPosVel + pVelVel + processNoisePos
        val newPPosVel = pPosVel + pVelVel
        val newPVelVel = pVelVel + processNoiseVel

        pPosPos = newPPosPos
        pPosVel = newPPosVel
        pVelVel = newPVelVel
    }

    /** Measurement update (H = [1, 0], scalar observation of position
     *  only): standard Kalman gain / state / covariance update. Must be
     *  called after [predict] in the same frame, per [KalmanBoxTracker]'s
     *  own "advance every frame, correct only on a real detection"
     *  discipline. */
    fun correct(measuredPos: Double) {
        val innovation = measuredPos - pos
        val innovationVariance = pPosPos + measurementNoise
        val kalmanGainPos = pPosPos / innovationVariance
        val kalmanGainVel = pPosVel / innovationVariance

        pos += kalmanGainPos * innovation
        vel += kalmanGainVel * innovation

        // P' = (I - K H) P, computed from the PRE-update P values throughout.
        val newPPosPos = pPosPos - kalmanGainPos * pPosPos
        val newPPosVel = pPosVel - kalmanGainPos * pPosVel
        val newPVelVel = pVelVel - kalmanGainVel * pPosVel

        pPosPos = newPPosPos
        pPosVel = newPPosVel
        pVelVel = newPVelVel
    }

    companion object {
        private const val INITIAL_UNCERTAINTY = 1000.0
    }
}

package com.spandan.app.camera

import android.graphics.Rect
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/**
 * [Segment 30] Pure rect-comparison math for the MediaPipe-vs-ML-Kit
 * validation step this migration's own task brief calls for: "before
 * trusting an fps number alone" for a candidate detector, log how far its
 * box actually lands from ML Kit's own box on the SAME frame -- a
 * faster-but-wrong box is not a win. No Android Image/Detection dependency,
 * so (like [CroppedDetectionStrategy]'s own pure rect math) this is directly
 * unit-testable the way [CoordinateMapperTest] tests [CoordinateMapper].
 *
 * Both boxes MUST already be in the SAME coordinate space before calling
 * either function here (this project's own rotated/upright space -- see
 * [CoordinateMapper.mediaPipeSensorBoxToRotatedRect]) -- comparing boxes from
 * two different spaces would silently produce a meaningless number instead
 * of an error, which is worse than not comparing them at all.
 */
object MediaPipeVsMlKitComparator {

    /**
     * Intersection-over-Union of two rects, in `[0.0, 1.0]`. `0.0` for
     * non-overlapping rects (including a zero-area rect on either side, which
     * can never contribute area). Field arithmetic only (`right - left`, not
     * `Rect.width()`) -- see [CroppedDetectionStrategy]'s own note on why
     * `Rect`'s methods are unsafe under this project's plain-JUnit harness.
     */
    fun intersectionOverUnion(a: Rect, b: Rect): Double {
        val aWidth = (a.right - a.left).coerceAtLeast(0)
        val aHeight = (a.bottom - a.top).coerceAtLeast(0)
        val bWidth = (b.right - b.left).coerceAtLeast(0)
        val bHeight = (b.bottom - b.top).coerceAtLeast(0)
        val aArea = aWidth.toDouble() * aHeight.toDouble()
        val bArea = bWidth.toDouble() * bHeight.toDouble()
        if (aArea <= 0.0 || bArea <= 0.0) return 0.0

        val interLeft = max(a.left, b.left)
        val interTop = max(a.top, b.top)
        val interRight = min(a.right, b.right)
        val interBottom = min(a.bottom, b.bottom)
        val interWidth = (interRight - interLeft).coerceAtLeast(0)
        val interHeight = (interBottom - interTop).coerceAtLeast(0)
        val interArea = interWidth.toDouble() * interHeight.toDouble()
        if (interArea <= 0.0) return 0.0

        val unionArea = aArea + bArea - interArea
        return interArea / unionArea
    }

    /**
     * Euclidean distance in pixels between the two rects' own centers.
     * Complements [intersectionOverUnion]: IoU alone conflates "same center,
     * different size" with "same size, different place," and this project's
     * own ROI (a fixed fractional sub-crop of the face box, see
     * [RoiCalculator]) cares about BOTH -- a same-size box shifted off the
     * real face would still miss the forehead even at a middling IoU.
     */
    fun centerDistance(a: Rect, b: Rect): Double {
        val aCenterX = (a.left + a.right) / 2.0
        val aCenterY = (a.top + a.bottom) / 2.0
        val bCenterX = (b.left + b.right) / 2.0
        val bCenterY = (b.top + b.bottom) / 2.0
        return hypot(aCenterX - bCenterX, aCenterY - bCenterY)
    }
}

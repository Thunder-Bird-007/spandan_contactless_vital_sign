package com.spandan.app.camera

import android.graphics.Rect
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Plain Kotlin/JUnit -- verifies [MediaPipeVsMlKitComparator]'s pure rect
 * math, the way [CroppedDetectionStrategyTest] tests [CroppedDetectionStrategy].
 *
 * IMPORTANT: every [Rect] here is built via [rectOf], never the 4-arg
 * `Rect(l,t,r,b)` constructor -- see [CroppedDetectionStrategyTest]'s own
 * header for why that constructor is a no-op (all fields stay 0) under this
 * project's plain-JUnit harness (`isReturnDefaultValues = true`).
 */
class MediaPipeVsMlKitComparatorTest {

    private fun rectOf(left: Int, top: Int, right: Int, bottom: Int): Rect {
        val r = Rect()
        r.left = left
        r.top = top
        r.right = right
        r.bottom = bottom
        return r
    }

    @Test
    fun intersectionOverUnion_isOneForIdenticalRects() {
        val a = rectOf(100, 100, 300, 300)
        val b = rectOf(100, 100, 300, 300)
        assertEquals(1.0, MediaPipeVsMlKitComparator.intersectionOverUnion(a, b), 1e-9)
    }

    @Test
    fun intersectionOverUnion_isZeroForNonOverlappingRects() {
        val a = rectOf(0, 0, 100, 100)
        val b = rectOf(200, 200, 300, 300)
        assertEquals(0.0, MediaPipeVsMlKitComparator.intersectionOverUnion(a, b), 1e-9)
    }

    @Test
    fun intersectionOverUnion_isZeroWhenRectsOnlyTouchAtAnEdge() {
        // Touching but not overlapping -- intersection width/height is 0.
        val a = rectOf(0, 0, 100, 100)
        val b = rectOf(100, 0, 200, 100)
        assertEquals(0.0, MediaPipeVsMlKitComparator.intersectionOverUnion(a, b), 1e-9)
    }

    @Test
    fun intersectionOverUnion_matchesHandComputedValueForPartialOverlap() {
        // a: [0,0,100,100] area=10000. b: [50,50,150,150] area=10000.
        // intersection: [50,50,100,100] area=2500. union = 10000+10000-2500=17500.
        val a = rectOf(0, 0, 100, 100)
        val b = rectOf(50, 50, 150, 150)
        val expected = 2500.0 / 17500.0
        assertEquals(expected, MediaPipeVsMlKitComparator.intersectionOverUnion(a, b), 1e-9)
    }

    @Test
    fun intersectionOverUnion_isZeroWhenEitherRectHasZeroArea() {
        val degenerate = rectOf(10, 10, 10, 50) // zero width
        val normal = rectOf(0, 0, 100, 100)
        assertEquals(0.0, MediaPipeVsMlKitComparator.intersectionOverUnion(degenerate, normal), 1e-9)
    }

    @Test
    fun centerDistance_isZeroForSameCenterDifferentSize() {
        val a = rectOf(0, 0, 100, 100) // center (50,50)
        val b = rectOf(25, 25, 75, 75) // center (50,50), smaller
        assertEquals(0.0, MediaPipeVsMlKitComparator.centerDistance(a, b), 1e-9)
    }

    @Test
    fun centerDistance_matchesHandComputedValue() {
        val a = rectOf(0, 0, 100, 100) // center (50,50)
        val b = rectOf(100, 100, 200, 200) // center (150,150)
        // distance between (50,50) and (150,150) = sqrt(100^2 + 100^2)
        val expected = Math.sqrt(100.0 * 100.0 + 100.0 * 100.0)
        assertEquals(expected, MediaPipeVsMlKitComparator.centerDistance(a, b), 1e-6)
    }
}

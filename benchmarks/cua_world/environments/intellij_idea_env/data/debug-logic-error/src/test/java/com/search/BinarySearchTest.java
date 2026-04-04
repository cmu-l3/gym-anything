package com.search;

import org.junit.Before;
import org.junit.Test;
import static org.junit.Assert.*;

/**
 * Tests for BinarySearch.
 * Several of these tests FAIL due to a logic bug in BinarySearch.search().
 * Use IntelliJ's debugger to trace the execution and identify why the method
 * returns -1 for elements that are clearly in the array.
 */
public class BinarySearchTest {

    private BinarySearch bs;

    @Before
    public void setUp() {
        bs = new BinarySearch();
    }

    @Test
    public void testSearchMiddleElement() {
        int[] arr = {1, 3, 5, 7, 9};
        assertEquals("Expected to find 5 at index 2", 2, bs.search(arr, 5));
    }

    @Test
    public void testSearchFirstElement() {
        int[] arr = {2, 4, 6, 8, 10};
        assertEquals("Expected to find 2 at index 0", 0, bs.search(arr, 2));
    }

    @Test
    public void testSearchLastElement() {
        // This test fails: when target is the last element and it becomes the only
        // candidate (left == right), the loop exits early without checking it.
        int[] arr = {1, 2, 3, 4, 5};
        assertEquals("Expected to find 5 at index 4", 4, bs.search(arr, 5));
    }

    @Test
    public void testSearchSingleElementFound() {
        // This test fails: with a single-element array, left==right==0 at loop start,
        // so the loop body never executes and -1 is returned immediately.
        int[] arr = {7};
        assertEquals("Expected to find 7 at index 0", 0, bs.search(arr, 7));
    }

    @Test
    public void testSearchSingleElementNotFound() {
        int[] arr = {7};
        assertEquals("Expected -1 when element not in array", -1, bs.search(arr, 3));
    }

    @Test
    public void testSearchNotPresent() {
        int[] arr = {1, 3, 5, 7, 9};
        assertEquals("Expected -1 for element not in array", -1, bs.search(arr, 4));
    }

    @Test
    public void testCountInRange() {
        int[] arr = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
        assertEquals("Elements in [3,7] should be 5", 5, bs.countInRange(arr, 3, 7));
    }

    @Test
    public void testCountInRangeWithDuplicates() {
        int[] arr = {1, 2, 2, 3, 3, 3, 4};
        assertEquals("Three 3s in range [3,3]", 3, bs.countInRange(arr, 3, 3));
    }

    @Test
    public void testEmptyArray() {
        assertEquals(-1, bs.search(new int[]{}, 5));
    }
}

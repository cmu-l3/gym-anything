package com.sorts;

import org.junit.Test;
import static org.junit.Assert.*;

/**
 * Tests for BubbleSort.
 *
 * NOTE: This test file contains 4 bugs that must be found and fixed.
 * Run the tests to see which ones fail, diagnose the cause of each failure,
 * and fix each issue independently.
 */
public class BubbleSortTest {

    private final BubbleSort sorter = new BubbleSort();

    @Test
    public void testEmptyArray() {
        int[] input = {};
        int[] result = sorter.sort(input);
        // BUG 1: assertEquals does not work for array comparison in JUnit 4.
        // It compares object references, not array contents.
        // Fix: use assertArrayEquals instead.
        assertEquals(new int[]{}, result);
    }

    @Test
    public void testSingleElement() {
        int[] input = {42};
        int[] result = sorter.sort(input);
        // BUG 2: Wrong expected value. A single-element array sorted is the same element.
        // Fix: change expected from {99} to {42}.
        assertArrayEquals(new int[]{99}, result);
    }

    @Test
    public void testUnsortedArray() {
        int[] input = {5, 3, 1, 4, 2};
        // BUG 3: The return value of sorter.sort() is not captured.
        // BubbleSort.sort() does NOT sort in place — it returns a new sorted array.
        // Fix: capture the result: int[] result = sorter.sort(input);
        sorter.sort(input);
        assertArrayEquals(new int[]{1, 2, 3, 4, 5}, input);
    }

    // BUG 4: Missing @Test annotation. This method will not be executed by the test runner.
    // Fix: add @Test annotation before the method signature.
    public void testAlreadySorted() {
        int[] input = {1, 2, 3, 4, 5};
        int[] result = sorter.sort(input);
        assertArrayEquals(new int[]{1, 2, 3, 4, 5}, result);
    }
}

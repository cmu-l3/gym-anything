package com.search;

/**
 * BinarySearch implementation with two search methods.
 * Based on TheAlgorithms/Java (https://github.com/TheAlgorithms/Java), Apache License 2.0.
 *
 * Requires a sorted input array. Uses divide-and-conquer to locate elements in O(log n) time.
 */
public class BinarySearch {

    /**
     * Searches for a target value in a sorted integer array.
     *
     * @param arr    sorted array to search (ascending order)
     * @param target value to find
     * @return index of target if found, -1 otherwise
     */
    public int search(int[] arr, int target) {
        if (arr == null || arr.length == 0) {
            return -1;
        }
        int left = 0;
        int right = arr.length - 1;

        // BUG: The loop condition uses strict less-than (<) instead of less-than-or-equal (<=).
        // When only one candidate remains (left == right), the loop exits without checking
        // arr[left] against the target. This causes the method to return -1 even when
        // the target is present as the final candidate.
        while (left < right) {
            int mid = left + (right - left) / 2;
            if (arr[mid] == target) {
                return mid;
            } else if (arr[mid] < target) {
                left = mid + 1;
            } else {
                right = mid - 1;
            }
        }
        return -1;
    }

    /**
     * Returns the count of elements in arr that fall within the closed range [lo, hi].
     * The array must be sorted in ascending order.
     *
     * @param arr sorted array
     * @param lo  lower bound (inclusive)
     * @param hi  upper bound (inclusive)
     * @return number of elements in [lo, hi]
     */
    public int countInRange(int[] arr, int lo, int hi) {
        if (arr == null || arr.length == 0 || lo > hi) {
            return 0;
        }
        int firstIdx = lowerBound(arr, lo);
        int lastIdx  = upperBound(arr, hi);
        return lastIdx - firstIdx;
    }

    // Returns the index of the first element >= value (standard lower_bound).
    private int lowerBound(int[] arr, int value) {
        int left = 0;
        int right = arr.length;
        while (left < right) {
            int mid = left + (right - left) / 2;
            if (arr[mid] < value) {
                left = mid + 1;
            } else {
                right = mid;
            }
        }
        return left;
    }

    // Returns the index of the first element > value (standard upper_bound).
    private int upperBound(int[] arr, int value) {
        int left = 0;
        int right = arr.length;
        while (left < right) {
            int mid = left + (right - left) / 2;
            if (arr[mid] <= value) {
                left = mid + 1;
            } else {
                right = mid;
            }
        }
        return left;
    }
}

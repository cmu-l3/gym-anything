package com.sorts;

/**
 * BubbleSort implementation.
 * Based on TheAlgorithms/Java (https://github.com/TheAlgorithms/Java), Apache License 2.0.
 *
 * Repeatedly steps through the list, compares adjacent elements and swaps them
 * if they are in the wrong order. Returns a new sorted array (does not sort in place).
 */
public class BubbleSort {

    /**
     * Sorts an integer array using the bubble sort algorithm.
     *
     * @param arr the input array to sort
     * @return a new sorted array (original array is NOT modified)
     */
    public int[] sort(int[] arr) {
        if (arr == null || arr.length <= 1) {
            return arr == null ? new int[0] : arr.clone();
        }
        int n = arr.length;
        int[] result = arr.clone();
        for (int i = 0; i < n - 1; i++) {
            for (int j = 0; j < n - i - 1; j++) {
                if (result[j] > result[j + 1]) {
                    int temp = result[j];
                    result[j] = result[j + 1];
                    result[j + 1] = temp;
                }
            }
        }
        return result;
    }
}

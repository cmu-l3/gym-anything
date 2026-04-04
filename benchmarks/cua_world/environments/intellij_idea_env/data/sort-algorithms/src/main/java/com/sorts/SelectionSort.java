package com.sorts;

/**
 * SelectionSort implementation.
 * Based on TheAlgorithms/Java (https://github.com/TheAlgorithms/Java), Apache License 2.0.
 *
 * Divides the array into a sorted and unsorted region. In each step, finds the
 * minimum element from the unsorted region and moves it to the end of the sorted region.
 */
public class SelectionSort {

    /**
     * Sorts an integer array in ascending order using selection sort.
     * Sorts the array in place.
     *
     * @param arr the array to sort (modified in place)
     */
    public void sort(int[] arr) {
        if (arr == null || arr.length <= 1) {
            return;
        }
        int n = arr.length;
        for (int i = 0; i < n - 1; i++) {
            int minIdx = i;
            for (int j = i + 1; j < n; j++) {
                if (arr[j] < arr[minIdx]) {
                    minIdx = j;
                }
            }
            if (minIdx != i) {
                int temp = arr[minIdx];
                arr[minIdx] = arr[i];
                arr[i] = temp;
            }
        }
    }
}

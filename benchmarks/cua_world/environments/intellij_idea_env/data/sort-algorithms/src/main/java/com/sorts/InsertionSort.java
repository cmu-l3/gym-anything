package com.sorts;

/**
 * InsertionSort implementation.
 * Based on TheAlgorithms/Java (https://github.com/TheAlgorithms/Java), Apache License 2.0.
 *
 * Builds the sorted array one element at a time by inserting each new element
 * into its correct position among the previously sorted elements.
 * Efficient for small or nearly-sorted datasets.
 */
public class InsertionSort {

    /**
     * Sorts an integer array in ascending order using insertion sort.
     * Sorts the array in place.
     *
     * @param arr the array to sort (modified in place)
     */
    public void sort(int[] arr) {
        if (arr == null || arr.length <= 1) {
            return;
        }
        for (int i = 1; i < arr.length; i++) {
            int key = arr[i];
            int j = i - 1;
            while (j >= 0 && arr[j] > key) {
                arr[j + 1] = arr[j];
                j--;
            }
            arr[j + 1] = key;
        }
    }
}

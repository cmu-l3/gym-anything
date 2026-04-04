package com.sorts;

import org.junit.Test;
import static org.junit.Assert.*;

public class InsertionSortTest {

    private final InsertionSort sorter = new InsertionSort();

    @Test
    public void testSortBasic() {
        int[] arr = {5, 3, 1, 4, 2};
        sorter.sort(arr);
        assertArrayEquals(new int[]{1, 2, 3, 4, 5}, arr);
    }

    @Test
    public void testSortAlreadySorted() {
        int[] arr = {1, 2, 3, 4, 5};
        sorter.sort(arr);
        assertArrayEquals(new int[]{1, 2, 3, 4, 5}, arr);
    }

    @Test
    public void testSortReverse() {
        int[] arr = {5, 4, 3, 2, 1};
        sorter.sort(arr);
        assertArrayEquals(new int[]{1, 2, 3, 4, 5}, arr);
    }

    @Test
    public void testSortSingleElement() {
        int[] arr = {42};
        sorter.sort(arr);
        assertArrayEquals(new int[]{42}, arr);
    }

    @Test
    public void testSortWithDuplicates() {
        int[] arr = {3, 1, 4, 1, 5, 9, 2, 6, 5};
        sorter.sort(arr);
        assertArrayEquals(new int[]{1, 1, 2, 3, 4, 5, 5, 6, 9}, arr);
    }
}

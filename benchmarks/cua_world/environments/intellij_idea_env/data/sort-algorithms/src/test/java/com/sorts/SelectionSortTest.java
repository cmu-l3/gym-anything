package com.sorts;

import org.junit.Test;
import static org.junit.Assert.*;

public class SelectionSortTest {

    private final SelectionSort sorter = new SelectionSort();

    @Test
    public void testSortBasic() {
        int[] arr = {64, 25, 12, 22, 11};
        sorter.sort(arr);
        assertArrayEquals(new int[]{11, 12, 22, 25, 64}, arr);
    }

    @Test
    public void testSortAlreadySorted() {
        int[] arr = {1, 2, 3};
        sorter.sort(arr);
        assertArrayEquals(new int[]{1, 2, 3}, arr);
    }

    @Test
    public void testSortWithNegatives() {
        int[] arr = {-3, 5, -1, 0, 4};
        sorter.sort(arr);
        assertArrayEquals(new int[]{-3, -1, 0, 4, 5}, arr);
    }
}

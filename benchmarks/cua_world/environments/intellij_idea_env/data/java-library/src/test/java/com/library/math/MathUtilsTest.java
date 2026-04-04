package com.library.math;

import org.junit.Test;
import static org.junit.Assert.*;

public class MathUtilsTest {

    @Test
    public void testGcd() {
        assertEquals(6, MathUtils.gcd(48, 18));
        assertEquals(1, MathUtils.gcd(7, 13));
        assertEquals(5, MathUtils.gcd(5, 0));
    }

    @Test
    public void testLcm() {
        assertEquals(12L, MathUtils.lcm(4, 6));
        assertEquals(0L, MathUtils.lcm(0, 5));
    }

    @Test
    public void testIsPrime() {
        assertTrue(MathUtils.isPrime(2));
        assertTrue(MathUtils.isPrime(17));
        assertFalse(MathUtils.isPrime(1));
        assertFalse(MathUtils.isPrime(9));
    }

    @Test
    public void testFibonacci() {
        assertEquals(0L, MathUtils.fibonacci(0));
        assertEquals(1L, MathUtils.fibonacci(1));
        assertEquals(55L, MathUtils.fibonacci(10));
    }
}

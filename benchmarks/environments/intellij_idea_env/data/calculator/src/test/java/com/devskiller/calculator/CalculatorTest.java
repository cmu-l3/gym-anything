package com.devskiller.calculator;

import org.junit.Test;
import static org.junit.Assert.*;

/**
 * JUnit tests for Calculator.
 */
public class CalculatorTest {

    private Calculator calculator = new Calculator();

    @Test
    public void testAdd() {
        assertEquals(5, calculator.add(2, 3));
    }

    @Test
    public void testSubtract() {
        assertEquals(1, calculator.subtract(3, 2));
    }

    @Test
    public void testMultiply() {
        assertEquals(6, calculator.multiply(2, 3));
    }

    @Test
    public void testDivide() {
        assertEquals(5, calculator.divide(10, 2));
    }

    @Test(expected = RuntimeException.class)
    public void testDivideByZero() {
        calculator.divide(10, 0);
    }
}

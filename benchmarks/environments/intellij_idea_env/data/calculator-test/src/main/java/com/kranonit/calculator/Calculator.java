package com.kranonit.calculator;

/**
 * Simple calculator with basic arithmetic operations.
 *
 * Based on the kranonit calculator-unit-test-example-java project
 * (https://github.com/kranonit/calculator-unit-test-example-java).
 *
 * This class has no tests - the agent must add JUnit dependency
 * and create test cases.
 */
public class Calculator {

    public double add(double a, double b) {
        return a + b;
    }

    public double subtract(double a, double b) {
        return a - b;
    }

    public double multiply(double a, double b) {
        return a * b;
    }

    public double divide(double a, double b) {
        if (b == 0) {
            throw new ArithmeticException("Cannot divide by zero");
        }
        return a / b;
    }
}

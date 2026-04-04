package org.lable.oss.helloworld;

/**
 * Calculator class for performing basic arithmetic operations.
 */
public class Calculator {

    public double calc(double x, double y, String o) {
        double result = 0;
        if (o.equals("add")) {
            System.out.println("Performing operation: " + o);
            System.out.println("Input: " + x + ", " + y);
            result = x + y;
            System.out.println("Result: " + result);
        } else if (o.equals("subtract")) {
            System.out.println("Performing operation: " + o);
            System.out.println("Input: " + x + ", " + y);
            result = x - y;
            System.out.println("Result: " + result);
        } else if (o.equals("multiply")) {
            System.out.println("Performing operation: " + o);
            System.out.println("Input: " + x + ", " + y);
            result = x * y;
            System.out.println("Result: " + result);
        } else if (o.equals("divide")) {
            System.out.println("Performing operation: " + o);
            System.out.println("Input: " + x + ", " + y);
            if (y == 0) {
                throw new ArithmeticException("Cannot divide by zero");
            }
            result = x / y;
            System.out.println("Result: " + result);
        }
        return result;
    }
}

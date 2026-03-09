package com.library.math;

/**
 * Mathematical utility functions.
 * Based on standard algorithm textbook patterns (Knuth, Sedgewick).
 *
 * These utilities form the "math" component of the library — a natural
 * candidate for its own Maven module due to having no dependency on
 * the collections or strings components.
 */
public class MathUtils {

    private MathUtils() {}

    /**
     * Computes the greatest common divisor of two positive integers
     * using the Euclidean algorithm.
     */
    public static int gcd(int a, int b) {
        if (a < 0 || b < 0) {
            throw new IllegalArgumentException("Arguments must be non-negative");
        }
        while (b != 0) {
            int t = b;
            b = a % b;
            a = t;
        }
        return a;
    }

    /**
     * Computes the least common multiple of two positive integers.
     */
    public static long lcm(int a, int b) {
        if (a == 0 || b == 0) return 0;
        return (long) a / gcd(a, b) * b;
    }

    /**
     * Returns true if n is a prime number.
     * Uses trial division up to sqrt(n).
     */
    public static boolean isPrime(int n) {
        if (n < 2) return false;
        if (n == 2) return true;
        if (n % 2 == 0) return false;
        for (int i = 3; (long) i * i <= n; i += 2) {
            if (n % i == 0) return false;
        }
        return true;
    }

    /**
     * Returns the n-th Fibonacci number (0-indexed: fib(0)=0, fib(1)=1).
     */
    public static long fibonacci(int n) {
        if (n < 0) throw new IllegalArgumentException("n must be non-negative");
        if (n == 0) return 0;
        long prev = 0, curr = 1;
        for (int i = 2; i <= n; i++) {
            long next = prev + curr;
            prev = curr;
            curr = next;
        }
        return curr;
    }
}

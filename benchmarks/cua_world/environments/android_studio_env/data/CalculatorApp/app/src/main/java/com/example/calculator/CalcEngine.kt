package com.example.calculator

/**
 * Core calculation engine for the calculator application.
 */
class CalcEngine {

    private var mem: Double = 0.0
    private var lastRes: Double = 0.0
    private var histList: MutableList<String> = mutableListOf()

    /**
     * Adds two numbers together.
     */
    fun doAdd(a: Double, b: Double): Double {
        val res = a + b
        lastRes = res
        histList.add("$a + $b = $res")
        return res
    }

    /**
     * Subtracts the second number from the first.
     */
    fun doSub(a: Double, b: Double): Double {
        val res = a - b
        lastRes = res
        histList.add("$a - $b = $res")
        return res
    }

    /**
     * Multiplies two numbers.
     */
    fun doMul(a: Double, b: Double): Double {
        val res = a * b
        lastRes = res
        histList.add("$a × $b = $res")
        return res
    }

    /**
     * Divides the first number by the second.
     *
     * @throws ArithmeticException if b is zero
     */
    fun doDiv(a: Double, b: Double): Double {
        if (b == 0.0) {
            throw ArithmeticException("Cannot divide by zero")
        }
        val res = a / b
        lastRes = res
        histList.add("$a ÷ $b = $res")
        return res
    }

    /**
     * Returns the remainder of dividing the first number by the second.
     *
     * @throws ArithmeticException if b is zero
     */
    fun doMod(a: Double, b: Double): Double {
        if (b == 0.0) {
            throw ArithmeticException("Cannot compute modulo with zero divisor")
        }
        val res = a % b
        lastRes = res
        histList.add("$a mod $b = $res")
        return res
    }

    /**
     * Raises the first number to the power of the second.
     */
    fun doPow(base: Double, exp: Double): Double {
        val res = Math.pow(base, exp)
        lastRes = res
        histList.add("$base ^ $exp = $res")
        return res
    }

    /**
     * Returns the square root of a number.
     *
     * @throws ArithmeticException if the number is negative
     */
    fun doSqrt(a: Double): Double {
        if (a < 0.0) {
            throw ArithmeticException("Cannot compute square root of a negative number")
        }
        val res = Math.sqrt(a)
        lastRes = res
        histList.add("√$a = $res")
        return res
    }

    /**
     * Negates a number (changes sign).
     */
    fun doNeg(a: Double): Double {
        val res = -a
        lastRes = res
        return res
    }

    /**
     * Returns the absolute value of a number.
     */
    fun doAbs(a: Double): Double {
        val res = Math.abs(a)
        lastRes = res
        return res
    }

    /**
     * Stores a value in memory.
     */
    fun memStore(value: Double) {
        mem = value
    }

    /**
     * Recalls the value stored in memory.
     */
    fun memRecall(): Double {
        return mem
    }

    /**
     * Adds a value to the current memory.
     */
    fun memAdd(value: Double) {
        mem += value
    }

    /**
     * Clears the memory.
     */
    fun memClear() {
        mem = 0.0
    }

    /**
     * Returns the last computed result.
     */
    fun getLastRes(): Double {
        return lastRes
    }

    /**
     * Returns the calculation history.
     */
    fun getHist(): List<String> {
        return histList.toList()
    }

    /**
     * Clears the calculation history.
     */
    fun clearHist() {
        histList.clear()
    }

    /**
     * Resets the calculator to initial state.
     */
    fun doReset() {
        mem = 0.0
        lastRes = 0.0
        histList.clear()
    }
}

package com.example.financialcalc

import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.sqrt

/**
 * Financial analyzer for investment performance metrics.
 *
 * No unit tests exist for this class. A QA engineer must create
 * comprehensive tests covering all methods, edge cases,
 * and exception scenarios.
 */
class InvestmentAnalyzer {

    /**
     * Calculates Return on Investment (ROI) as a percentage.
     *
     * @param initialValue The original investment amount (must be > 0)
     * @param finalValue   The current value of the investment
     * @return ROI as percentage (e.g., 25.0 means 25% return)
     * @throws ArithmeticException if initialValue is zero
     * @throws IllegalArgumentException if initialValue is negative
     */
    fun calculateROI(initialValue: Double, finalValue: Double): Double {
        require(initialValue > 0) { "Initial value must be positive, got: $initialValue" }
        return (finalValue - initialValue) / initialValue * 100.0
    }

    /**
     * Calculates Compound Annual Growth Rate (CAGR).
     *
     * @param initialValue Starting value of the investment (must be > 0)
     * @param finalValue   Ending value of the investment
     * @param years        Number of years (must be > 0)
     * @return CAGR as percentage
     */
    fun calculateCAGR(initialValue: Double, finalValue: Double, years: Double): Double {
        require(years > 0) { "Years must be positive, got: $years" }
        require(initialValue > 0) { "Initial value must be positive, got: $initialValue" }
        require(finalValue > 0) { "Final value must be positive, got: $finalValue" }
        return ((finalValue / initialValue).pow(1.0 / years) - 1) * 100.0
    }

    /**
     * Calculates future value using compound interest formula.
     *
     * @param principal  Initial investment amount
     * @param annualRate Annual interest rate as decimal (e.g., 0.07 for 7%)
     * @param years      Number of years
     * @param n          Compounding frequency per year (e.g., 12 for monthly)
     * @return Future value of the investment
     */
    fun calculateCompoundInterest(
        principal: Double,
        annualRate: Double,
        years: Int,
        n: Int
    ): Double {
        require(principal > 0) { "Principal must be positive" }
        require(years > 0) { "Years must be positive" }
        require(n > 0) { "Compounding frequency must be positive" }
        return principal * (1 + annualRate / n).pow((n * years).toDouble())
    }

    /**
     * Calculates the Sharpe Ratio — a measure of risk-adjusted return.
     *
     * @param portfolioReturn  Annualized portfolio return as decimal
     * @param riskFreeRate     Risk-free rate of return as decimal
     * @param stdDeviation     Standard deviation of portfolio returns
     * @return Sharpe Ratio
     * @throws ArithmeticException if stdDeviation is zero
     */
    fun calculateSharpeRatio(
        portfolioReturn: Double,
        riskFreeRate: Double,
        stdDeviation: Double
    ): Double {
        require(stdDeviation >= 0) { "Standard deviation cannot be negative" }
        if (stdDeviation == 0.0) throw ArithmeticException("Standard deviation cannot be zero for Sharpe Ratio")
        return (portfolioReturn - riskFreeRate) / stdDeviation
    }

    /**
     * Calculates simple portfolio volatility (standard deviation of returns).
     *
     * @param returns List of periodic return values
     * @return Standard deviation of the returns, or 0.0 if fewer than 2 data points
     */
    fun calculateVolatility(returns: List<Double>): Double {
        if (returns.size < 2) return 0.0
        val mean = returns.average()
        val variance = returns.sumOf { (it - mean) * (it - mean) } / (returns.size - 1)
        return sqrt(variance)
    }
}

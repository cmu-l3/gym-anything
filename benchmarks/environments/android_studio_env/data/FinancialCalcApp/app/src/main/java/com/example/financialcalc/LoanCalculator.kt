package com.example.financialcalc

import kotlin.math.pow

/**
 * Financial calculator for loan/mortgage computations.
 *
 * This class has zero test coverage. A QA engineer must add
 * comprehensive unit tests covering all methods, edge cases,
 * and exception handling.
 */
class LoanCalculator {

    /**
     * Calculates the fixed monthly payment for a fully amortizing loan.
     *
     * @param principal  The loan amount in dollars (must be > 0)
     * @param annualRate The annual interest rate as a percentage (e.g., 6.5 for 6.5%)
     * @param months     The loan term in months (must be > 0)
     * @return Monthly payment amount
     * @throws IllegalArgumentException if inputs are invalid
     */
    fun calculateMonthlyPayment(principal: Double, annualRate: Double, months: Int): Double {
        require(principal > 0) { "Principal must be positive, got: $principal" }
        require(months > 0) { "Loan term must be positive, got: $months" }
        require(annualRate >= 0) { "Annual rate cannot be negative, got: $annualRate" }

        // Zero-interest loan: equal monthly payments
        if (annualRate == 0.0) return principal / months

        val monthlyRate = annualRate / 100.0 / 12.0
        val factor = (1 + monthlyRate).pow(months.toDouble())
        return principal * monthlyRate * factor / (factor - 1)
    }

    /**
     * Calculates total interest paid over the life of the loan.
     */
    fun calculateTotalInterest(principal: Double, annualRate: Double, months: Int): Double {
        val monthly = calculateMonthlyPayment(principal, annualRate, months)
        return monthly * months - principal
    }

    /**
     * Calculates the remaining principal balance after [paymentsMade] payments.
     *
     * @param paymentsMade Number of payments already made
     * @return Remaining balance (0.0 if loan is fully paid)
     */
    fun calculateRemainingBalance(
        principal: Double,
        annualRate: Double,
        months: Int,
        paymentsMade: Int
    ): Double {
        require(paymentsMade >= 0) { "Payments made cannot be negative" }
        if (paymentsMade >= months) return 0.0
        if (annualRate == 0.0) return principal - (principal / months * paymentsMade)

        val monthlyRate = annualRate / 100.0 / 12.0
        val monthly = calculateMonthlyPayment(principal, annualRate, months)
        return principal * (1 + monthlyRate).pow(paymentsMade.toDouble()) -
               monthly * ((1 + monthlyRate).pow(paymentsMade.toDouble()) - 1) / monthlyRate
    }

    /**
     * Determines if a borrower is eligible for a loan based on credit profile.
     *
     * @param creditScore      FICO credit score (300–850)
     * @param debtToIncomeRatio Debt-to-income ratio (0.0–1.0, e.g., 0.35 = 35%)
     * @return true if eligible (score >= 620 AND DTI <= 0.43)
     */
    fun isEligibleForLoan(creditScore: Int, debtToIncomeRatio: Double): Boolean {
        return creditScore >= 620 && debtToIncomeRatio <= 0.43
    }

    /**
     * Calculates maximum affordable loan amount given a target monthly payment.
     *
     * @param targetMonthlyPayment Maximum monthly payment the borrower can afford
     * @param annualRate Annual interest rate as percentage
     * @param months Loan term in months
     * @return Maximum principal amount
     */
    fun calculateMaxLoanAmount(
        targetMonthlyPayment: Double,
        annualRate: Double,
        months: Int
    ): Double {
        require(targetMonthlyPayment > 0) { "Target payment must be positive" }
        require(months > 0) { "Months must be positive" }
        if (annualRate == 0.0) return targetMonthlyPayment * months

        val monthlyRate = annualRate / 100.0 / 12.0
        val factor = (1 + monthlyRate).pow(months.toDouble())
        return targetMonthlyPayment * (factor - 1) / (monthlyRate * factor)
    }
}

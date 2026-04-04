package com.example.financialcalc

/**
 * Personal budget planning utilities.
 *
 * No unit tests exist. QA engineer must write tests covering all
 * public methods with normal cases, edge cases, and error conditions.
 */
class BudgetPlanner {

    /**
     * Calculates the percentage of income saved after expenses.
     *
     * @param monthlyIncome   Gross monthly income (must be > 0)
     * @param monthlyExpenses Total monthly expenses
     * @return Savings rate as a percentage (negative if spending exceeds income)
     * @throws IllegalArgumentException if income is not positive
     */
    fun calculateSavingsRate(monthlyIncome: Double, monthlyExpenses: Double): Double {
        require(monthlyIncome > 0) { "Monthly income must be positive, got: $monthlyIncome" }
        return (monthlyIncome - monthlyExpenses) / monthlyIncome * 100.0
    }

    /**
     * Calculates the recommended emergency fund target.
     *
     * @param monthlyExpenses Average monthly expenses
     * @param months          Number of months of expenses to cover (default: 6)
     * @return Target emergency fund amount
     * @throws IllegalArgumentException if months < 1
     */
    fun calculateEmergencyFundTarget(monthlyExpenses: Double, months: Int = 6): Double {
        require(months >= 1) { "Months must be at least 1, got: $months" }
        require(monthlyExpenses >= 0) { "Monthly expenses cannot be negative" }
        return monthlyExpenses * months
    }

    /**
     * Applies percentage-based budget allocations to an income amount.
     *
     * @param income      Monthly income
     * @param allocations Map of category name to percentage (e.g., "Housing" to 30.0)
     * @return Map of category to dollar amount
     * @throws IllegalArgumentException if total allocations exceed 100%
     */
    fun applyBudgetAllocations(
        income: Double,
        allocations: Map<String, Double>
    ): Map<String, Double> {
        val totalPct = allocations.values.sum()
        require(totalPct <= 100.0) {
            "Total allocations (${totalPct}%) exceed 100%"
        }
        return allocations.mapValues { (_, pct) -> income * pct / 100.0 }
    }

    /**
     * Calculates months needed to reach a savings goal.
     *
     * @param currentSavings  Current savings balance
     * @param goal            Target savings amount
     * @param monthlySavings  Amount saved each month
     * @return Number of months to reach the goal (0 if already reached)
     * @throws IllegalArgumentException if monthlySavings <= 0
     */
    fun calculateMonthsToGoal(
        currentSavings: Double,
        goal: Double,
        monthlySavings: Double
    ): Int {
        require(monthlySavings > 0) { "Monthly savings must be positive, got: $monthlySavings" }
        if (currentSavings >= goal) return 0
        return kotlin.math.ceil((goal - currentSavings) / monthlySavings).toInt()
    }

    /**
     * Evaluates whether spending in each category is within the allocated budget.
     *
     * @param budgeted Map of category to budgeted amount
     * @param actual   Map of category to actual spending
     * @return Map of category to over/under budget amount (positive = under, negative = over)
     */
    fun evaluateBudgetVariances(
        budgeted: Map<String, Double>,
        actual: Map<String, Double>
    ): Map<String, Double> {
        return budgeted.mapValues { (category, budget) ->
            budget - (actual[category] ?: 0.0)
        }
    }
}

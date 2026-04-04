# Task: Add Comprehensive Unit Tests

## Overview
Write comprehensive JUnit unit tests for the three financial calculation classes in FinancialCalcApp. The project currently has zero test coverage.

## Classes to Test

### LoanCalculator
- `calculateMonthlyPayment(principal, annualRate, months)` → standard amortization formula
- `calculateTotalInterest()` → `totalPayment - principal`
- `calculateRemainingBalance(monthsPaid)` → remaining amortized balance
- `isEligibleForLoan(creditScore, debtToIncomeRatio)` → returns Boolean
- `calculateMaxLoanAmount()` → based on monthly income

### InvestmentAnalyzer
- `calculateROI()` → `(currentValue - initialInvestment) / initialInvestment * 100`
- `calculateCAGR(years)` → Compound Annual Growth Rate
- `calculateCompoundInterest(rate, n, t)` → A = P(1+r/n)^(nt)
- `calculateSharpeRatio()` → `(returns - riskFreeRate) / stdDeviation` (throws if stdDeviation == 0)
- `calculateVolatility()` → std deviation of returns list

### BudgetPlanner
- `calculateSavingsRate()` → `savings / income * 100`
- `calculateEmergencyFundTarget()` → `monthlyExpenses * 6`
- `applyBudgetAllocations()` → allocates income by category percentages
- `calculateMonthsToGoal(targetAmount)` → months to reach savings goal
- `evaluateBudgetVariances()` → map of category → (actual - budgeted)

## Required Test Location
`app/src/test/java/com/example/financialcalc/`

Example test files:
- `LoanCalculatorTest.kt`
- `InvestmentAnalyzerTest.kt`
- `BudgetPlannerTest.kt`

## Scoring
- Test files created (at least 1): 15 pts
- At least 15 @Test methods total: 20 pts
- Tests cover at least 2 of the 3 classes: 15 pts
- Edge case / exception tests present: 20 pts
- All tests pass (./gradlew test): 30 pts

Pass threshold: 70/100

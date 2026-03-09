# Task: qa_test_suite_coverage

## Domain Context

**Primary occupation**: QA Engineers / Test Automation Engineers (Fintech sector)

A fintech company shipped the `FinancialCalc` library with zero automated tests. The CI/CD pipeline now requires a test suite before any PR can merge. The QA engineer must write comprehensive xUnit tests from scratch, covering all three calculator classes.

This is a `hard` task because:
- The agent must write enough tests to cover all classes (9+ test methods)
- Tests must be behaviorally correct (assert accurate expected values)
- Must include exception paths (not just happy path)
- The `CurrencyConverter` multi-hop routing is a non-trivial algorithmic feature to test

## Library Under Test

### `LoanCalculator`
- `MonthlyPayment(principal, annualRate, termMonths)` → monthly payment using standard amortization formula
- `TotalInterest(principal, annualRate, termMonths)` → total interest = monthly × months − principal
- Throws `ArgumentException` for: principal ≤ 0, annualRate < 0, termMonths < 1
- Edge case: annualRate = 0 → monthly = principal / termMonths

### `CompoundInterestEngine`
- `FutureValue(principal, annualRate, compoundingFrequency, years)` → P × (1 + r/n)^(n×t)
- `InterestEarned(...)` → FutureValue − principal
- Throws `ArgumentException` for: principal < 0, annualRate < 0, freq < 1, years < 0

### `CurrencyConverter`
- `AddRate(from, to, rate)` → registers direct rate + automatic inverse
- `Convert(amount, from, to)` → direct conversion; falls back to 2-hop routing
- Throws `InvalidOperationException` when no conversion path exists
- Throws `ArgumentException` for: empty codes, rate ≤ 0, negative amount

## Success Criteria

| Criterion | Points | Check |
|-----------|--------|-------|
| Test file meaningfully modified (not placeholder) | 10 | Real test classes present |
| LoanCalculator tests exist | 15 | `LoanCalculator` referenced in test file |
| CompoundInterestEngine tests exist | 15 | `CompoundInterestEngine` referenced |
| CurrencyConverter tests exist | 15 | `CurrencyConverter` referenced |
| Exception/error scenarios tested | 10 | `Assert.Throws<>` or `ThrowsException` present |
| Edge cases tested (zero rate, etc.) | 5 | Zero/boundary values in tests |
| Total test method count ≥ 9 | 10 | `[Fact]` + `[Theory]` count ≥ 9 |
| All tests pass (0 failures) | 10 | dotnet test result |
| Build: 0 errors | 10 | dotnet build |

**Pass threshold**: 60 points
**Build gate**: If build has errors, score is capped at 40

## Correct Expected Values (for agent to use in assertions)

```
LoanCalculator.MonthlyPayment(100000, 0.06, 360) ≈ 599.55
LoanCalculator.MonthlyPayment(50000, 0.0, 12)   = 4166.67
LoanCalculator.TotalInterest(100000, 0.06, 360) ≈ 115838.19

CompoundInterestEngine.FutureValue(1000, 0.05, 12, 10) ≈ 1647.01
CompoundInterestEngine.FutureValue(1000, 0.0, 1, 5)    = 1000.00

CurrencyConverter: AddRate("USD","EUR",0.92); Convert(100,"USD","EUR") = 92.0
CurrencyConverter: no path → InvalidOperationException
```

## Verification Strategy

`export_result.ps1`:
1. Kills VS to flush edits
2. Reads `FinancialCalcTests.cs`
3. Counts `[Fact]` and `[Theory]` decorators
4. Checks for class references, exception patterns, edge case patterns
5. Runs `dotnet build` then `dotnet test`
6. Captures pass/fail counts
7. Writes result JSON to `C:\Users\Docker\qa_test_suite_coverage_result.json`

`verifier.py`:
1. Copies result JSON + test file
2. Independent analysis of test content
3. Per-criterion scoring with partial credit
4. Checks all-tests-passed from dotnet test output

# Task: portfolio_risk_engine

## Domain Context

**Primary occupation**: Financial Quantitative Analysts, Risk Analysts (Investment Banking GDP ~$622M+)

Atlas Capital Management runs a multi-asset portfolio and needs production-ready risk analytics. The risk team scaffolded a .NET 8 `PortfolioAnalytics` library defining the interface contract (`IPortfolioRiskCalculator`) and three calculator classes — but all three implementations are empty stubs returning `0.0`. The head of risk needs real numbers before markets open.

The three metrics are standard in institutional finance:
- **Value-at-Risk (VaR)**: How much could the portfolio lose on a bad day?
- **Sharpe Ratio**: Is the portfolio generating returns that justify its risk level?
- **Maximum Drawdown**: What was the worst peak-to-trough loss over the period?

## Task Description

The agent must read the existing interface contract and stub implementations in the open VS 2022 solution, understand the required algorithm from the class-level XML doc comments, and implement each calculator correctly. The solution must build with 0 errors.

**The agent is NOT told the precise formulas — it must apply quantitative finance domain knowledge or infer the formula from the documentation comments in each class.**

## Success Criteria

| Criterion | Points | What to check |
|-----------|--------|---------------|
| VaRCalculator: Sort + percentile index (floor(n×0.05)) | 15 | Sort call + 0.05 / Floor present in VaRCalculator.cs |
| VaRCalculator: Negate to express as positive loss | 8 | Negation pattern present |
| VaRCalculator: Real logic (not stub) | 7 | At least one of: Sort, LINQ, loop, Math function |
| SharpeRatioCalculator: sqrt(252) annualization | 12 | Math.Sqrt(252) pattern |
| SharpeRatioCalculator: Mean + std dev computation | 12 | Average() + std dev pattern |
| SharpeRatioCalculator: Risk-free rate incorporated | 11 | Division by 252 and use in formula |
| MaxDrawdownCalculator: Running peak tracking | 10 | `peak` variable / high-water mark |
| MaxDrawdownCalculator: Drawdown as fraction | 10 | (peak - cumulative) / peak expression |
| Build: 0 errors | 15 | dotnet build succeeds |

**Pass threshold**: 60 points
**Build gate**: If build has errors, score is capped at 50

## Correct Algorithm Reference (for verifier ground truth)

### VaR (Historical Simulation, 95% confidence)
```csharp
var sorted = new List<double>(dailyReturns);
sorted.Sort();
int idx = (int)Math.Floor(sorted.Count * 0.05);
return -sorted[idx];  // negate — VaR is quoted as a positive loss
```

### Sharpe Ratio (annualized)
```csharp
double rfDaily = config["risk_free_annual"] / 252.0;
double mean    = dailyReturns.Average();
double stddev  = Math.Sqrt(dailyReturns.Average(r => Math.Pow(r - mean, 2)));
return (mean - rfDaily) / stddev * Math.Sqrt(252);
```

### Max Drawdown (peak-to-trough as fraction)
```csharp
double peak = double.MinValue, cumSum = 0, maxDD = 0;
foreach (var r in dailyReturns) {
    cumSum += r;
    if (cumSum > peak) peak = cumSum;
    if (peak > 0) maxDD = Math.Max(maxDD, (peak - cumSum) / peak);
}
return maxDD;
```

## Verification Strategy

`export_result.ps1`:
1. Kills VS to flush any unsaved edits
2. Reads each calculator source file
3. Static analysis: checks for stub (no real logic) vs. real implementation
4. Detects algorithm-specific patterns via regex
5. Runs `dotnet build` and captures error count
6. Writes result JSON to `C:\Users\Docker\portfolio_risk_engine_result.json`

`verifier.py`:
1. Copies result JSON from VM
2. Independently copies each `.cs` source file and re-applies regex
3. Scores each criterion independently with partial credit
4. Applies build gate (caps at 50 if build fails)

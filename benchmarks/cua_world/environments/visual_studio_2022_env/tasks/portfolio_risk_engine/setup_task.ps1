<#
  setup_task.ps1 - PortfolioAnalytics risk engine task setup
  Creates a .NET 8 class library with interface contracts and empty stub implementations.
  The agent must implement VaR, Sharpe Ratio, and Max Drawdown correctly.
#>

. "C:\workspace\scripts\task_utils.ps1"

$ProjectDir = "C:\Users\Docker\source\repos\PortfolioAnalytics"
$SrcDir     = "$ProjectDir\src\PortfolioAnalytics"
$TestDir    = "$ProjectDir\src\PortfolioAnalytics.Tests"
$SlnFile    = "$ProjectDir\PortfolioAnalytics.sln"

Write-Host "=== Setting up portfolio_risk_engine task ==="

# ── 1. Clean any prior run ────────────────────────────────────────────────────
Kill-AllVS2022
Start-Sleep -Seconds 2

if (Test-Path $ProjectDir) {
    Remove-Item $ProjectDir -Recurse -Force
}
New-Item -ItemType Directory -Path $SrcDir  -Force | Out-Null
New-Item -ItemType Directory -Path $TestDir -Force | Out-Null

# ── 2. Main library project file ──────────────────────────────────────────────
@'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>disable</ImplicitUsings>
    <RootNamespace>PortfolioAnalytics</RootNamespace>
    <AssemblyName>PortfolioAnalytics</AssemblyName>
  </PropertyGroup>
</Project>
'@ | Set-Content "$SrcDir\PortfolioAnalytics.csproj" -Encoding UTF8

# ── 3. Interface ──────────────────────────────────────────────────────────────
@'
using System.Collections.Generic;

namespace PortfolioAnalytics
{
    /// <summary>
    /// Contract for all portfolio risk metric calculators.
    /// Calculate() receives a list of daily P&amp;L returns (as decimals, e.g. 0.012 = +1.2%)
    /// and an optional configuration dictionary.
    /// It returns the computed metric value.
    /// </summary>
    public interface IPortfolioRiskCalculator
    {
        double Calculate(List<double> dailyReturns, Dictionary<string, double>? config = null);
    }
}
'@ | Set-Content "$SrcDir\IPortfolioRiskCalculator.cs" -Encoding UTF8

# ── 4. VaRCalculator stub ─────────────────────────────────────────────────────
@'
using System;
using System.Collections.Generic;

namespace PortfolioAnalytics
{
    /// <summary>
    /// Historical Simulation Value-at-Risk at 95% confidence level.
    /// Returns the loss (positive number) at the 5th percentile of the return distribution.
    /// </summary>
    public class VaRCalculator : IPortfolioRiskCalculator
    {
        public double Calculate(List<double> dailyReturns, Dictionary<string, double>? config = null)
        {
            // TODO: Implement historical simulation VaR at 95% confidence.
            // 1. Sort returns ascending.
            // 2. Take the value at index floor(n * 0.05).
            // 3. Negate it to express as a positive loss (VaR is quoted as positive).
            // If n == 0, return 0.
            return 0.0;
        }
    }
}
'@ | Set-Content "$SrcDir\VaRCalculator.cs" -Encoding UTF8

# ── 5. SharpeRatioCalculator stub ─────────────────────────────────────────────
@'
using System;
using System.Collections.Generic;
using System.Linq;

namespace PortfolioAnalytics
{
    /// <summary>
    /// Annualized Sharpe Ratio calculator.
    /// config must contain "risk_free_annual" (annual risk-free rate as decimal, e.g. 0.04).
    /// Formula: (mean_daily - rf_daily) / stddev_daily * sqrt(252)
    /// where rf_daily = risk_free_annual / 252.
    /// </summary>
    public class SharpeRatioCalculator : IPortfolioRiskCalculator
    {
        public double Calculate(List<double> dailyReturns, Dictionary<string, double>? config = null)
        {
            // TODO: Implement annualized Sharpe Ratio.
            // 1. Extract risk_free_annual from config (default 0.0 if missing).
            // 2. Compute rf_daily = risk_free_annual / 252.
            // 3. Compute mean of dailyReturns.
            // 4. Compute sample std dev of dailyReturns.
            // 5. If stddev == 0, return 0.
            // 6. Return (mean - rf_daily) / stddev * Math.Sqrt(252).
            return 0.0;
        }
    }
}
'@ | Set-Content "$SrcDir\SharpeRatioCalculator.cs" -Encoding UTF8

# ── 6. MaxDrawdownCalculator stub ─────────────────────────────────────────────
@'
using System.Collections.Generic;

namespace PortfolioAnalytics
{
    /// <summary>
    /// Maximum Drawdown calculator.
    /// Returns the maximum peak-to-trough decline as a positive fraction (0 to 1).
    /// Operates on cumulative P&amp;L (running sum of returns).
    /// </summary>
    public class MaxDrawdownCalculator : IPortfolioRiskCalculator
    {
        public double Calculate(List<double> dailyReturns, Dictionary<string, double>? config = null)
        {
            // TODO: Implement maximum drawdown.
            // 1. Track running cumulative sum and running peak.
            // 2. At each step: cumulativeSum += dailyReturns[i].
            // 3. If cumulativeSum > peak, update peak = cumulativeSum.
            // 4. If peak > 0: drawdown = (peak - cumulativeSum) / peak.
            // 5. Track maxDrawdown = max(maxDrawdown, drawdown).
            // 6. Return maxDrawdown (positive fraction).
            return 0.0;
        }
    }
}
'@ | Set-Content "$SrcDir\MaxDrawdownCalculator.cs" -Encoding UTF8

# ── 7. PortfolioRiskEngine (wires the calculators together) ───────────────────
@'
using System.Collections.Generic;

namespace PortfolioAnalytics
{
    /// <summary>
    /// Orchestrates all risk metric calculations for a portfolio.
    /// </summary>
    public class PortfolioRiskEngine
    {
        private readonly VaRCalculator         _var     = new VaRCalculator();
        private readonly SharpeRatioCalculator _sharpe  = new SharpeRatioCalculator();
        private readonly MaxDrawdownCalculator _mdd     = new MaxDrawdownCalculator();

        public RiskReport ComputeRisk(List<double> dailyReturns, double riskFreeAnnual = 0.04)
        {
            var cfg = new Dictionary<string, double> { ["risk_free_annual"] = riskFreeAnnual };
            return new RiskReport
            {
                VaR95          = _var.Calculate(dailyReturns, cfg),
                SharpeRatio    = _sharpe.Calculate(dailyReturns, cfg),
                MaxDrawdown    = _mdd.Calculate(dailyReturns, cfg),
            };
        }
    }

    public class RiskReport
    {
        public double VaR95       { get; set; }
        public double SharpeRatio { get; set; }
        public double MaxDrawdown { get; set; }
    }
}
'@ | Set-Content "$SrcDir\PortfolioRiskEngine.cs" -Encoding UTF8

# ── 8. Build to confirm stubs compile (all returns 0 — no errors) ─────────────
$dotnet = Find-DotnetExe
Write-Host "Building stub project to confirm it compiles..."
& $dotnet build "$SrcDir\PortfolioAnalytics.csproj" --configuration Release 2>&1 | Write-Host

# ── 9. Create solution ────────────────────────────────────────────────────────
Push-Location $ProjectDir
& $dotnet new sln --name PortfolioAnalytics --force 2>&1 | Out-Null
& $dotnet sln add "$SrcDir\PortfolioAnalytics.csproj" 2>&1 | Out-Null
Pop-Location

# ── 10. Record task-start timestamp AFTER writing files ───────────────────────
Start-Sleep -Seconds 2
$taskStart = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$taskStart | Set-Content "C:\Users\Docker\portfolio_risk_engine_start_ts.txt" -Encoding UTF8

Write-Host "Task start timestamp recorded: $taskStart"

# ── 11. Launch VS 2022 with the solution ─────────────────────────────────────
Write-Host "Launching Visual Studio 2022..."
$devenvExe = Find-VS2022Exe
Launch-VS2022Interactive -DevenvExe $devenvExe -SolutionPath $SlnFile -WaitSeconds 25

Write-Host "Dismissing first-run VS dialogs..."
try { Dismiss-VSDialogsBestEffort -Retries 3 -InitialWaitSeconds 5 -BetweenRetriesSeconds 2 }
catch { Write-Host "WARNING: Dialog dismissal: $($_.Exception.Message)" }

Write-Host "=== portfolio_risk_engine setup complete ==="

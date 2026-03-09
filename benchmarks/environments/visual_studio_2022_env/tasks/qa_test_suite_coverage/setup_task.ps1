<#
  setup_task.ps1 - FinancialCalc QA test suite coverage task
  Creates a working FinancialCalc library and an empty FinancialCalc.Tests project.
  Agent must write comprehensive xUnit tests to achieve coverage.
#>

. "C:\workspace\scripts\task_utils.ps1"

$ProjectDir  = "C:\Users\Docker\source\repos\FinancialCalc"
$LibDir      = "$ProjectDir\src\FinancialCalc"
$TestDir     = "$ProjectDir\src\FinancialCalc.Tests"
$SlnFile     = "$ProjectDir\FinancialCalc.sln"

Write-Host "=== Setting up qa_test_suite_coverage task ==="

# ── 1. Clean prior run ────────────────────────────────────────────────────────
Kill-AllVS2022
Start-Sleep -Seconds 2

if (Test-Path $ProjectDir) {
    Remove-Item $ProjectDir -Recurse -Force
}
New-Item -ItemType Directory -Path $LibDir  -Force | Out-Null
New-Item -ItemType Directory -Path $TestDir -Force | Out-Null

# ── 2. Library project file ───────────────────────────────────────────────────
@'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>disable</ImplicitUsings>
    <RootNamespace>FinancialCalc</RootNamespace>
    <AssemblyName>FinancialCalc</AssemblyName>
  </PropertyGroup>
</Project>
'@ | Set-Content "$LibDir\FinancialCalc.csproj" -Encoding UTF8

# ── 3. LoanCalculator.cs ──────────────────────────────────────────────────────
@'
using System;

namespace FinancialCalc
{
    /// <summary>
    /// Fixed-rate installment loan calculator.
    /// </summary>
    public class LoanCalculator
    {
        /// <summary>
        /// Calculate the monthly payment for a fixed-rate loan.
        /// Formula: M = P * [r(1+r)^n] / [(1+r)^n - 1]
        /// where r = monthly rate = annualRate / 12
        /// </summary>
        /// <param name="principal">Loan principal (must be > 0)</param>
        /// <param name="annualRate">Annual interest rate as a decimal (e.g., 0.06 for 6%)</param>
        /// <param name="termMonths">Loan term in months (must be >= 1)</param>
        /// <returns>Monthly payment amount</returns>
        /// <exception cref="ArgumentException">Thrown when inputs are invalid</exception>
        public double MonthlyPayment(double principal, double annualRate, int termMonths)
        {
            if (principal <= 0)
                throw new ArgumentException("Principal must be positive", nameof(principal));
            if (annualRate < 0)
                throw new ArgumentException("Annual rate cannot be negative", nameof(annualRate));
            if (termMonths < 1)
                throw new ArgumentException("Term must be at least 1 month", nameof(termMonths));

            if (annualRate == 0.0)
                return principal / termMonths;

            double r = annualRate / 12.0;
            double factor = Math.Pow(1 + r, termMonths);
            return principal * (r * factor) / (factor - 1);
        }

        /// <summary>
        /// Calculate the total interest paid over the life of the loan.
        /// </summary>
        public double TotalInterest(double principal, double annualRate, int termMonths)
        {
            double monthly = MonthlyPayment(principal, annualRate, termMonths);
            return monthly * termMonths - principal;
        }
    }
}
'@ | Set-Content "$LibDir\LoanCalculator.cs" -Encoding UTF8

# ── 4. CompoundInterestEngine.cs ──────────────────────────────────────────────
@'
using System;

namespace FinancialCalc
{
    /// <summary>
    /// Future value calculator with periodic compounding.
    /// </summary>
    public class CompoundInterestEngine
    {
        /// <summary>
        /// Compute the future value of an investment with compound interest.
        /// Formula: FV = P * (1 + r/n)^(n*t)
        /// </summary>
        /// <param name="principal">Initial investment (must be >= 0)</param>
        /// <param name="annualRate">Annual interest rate as decimal (e.g., 0.05 for 5%)</param>
        /// <param name="compoundingFrequency">Number of compounding periods per year (e.g., 12 for monthly)</param>
        /// <param name="years">Investment duration in years (must be >= 0)</param>
        /// <returns>Future value</returns>
        /// <exception cref="ArgumentException">Thrown when inputs are invalid</exception>
        public double FutureValue(double principal, double annualRate, int compoundingFrequency, double years)
        {
            if (principal < 0)
                throw new ArgumentException("Principal cannot be negative", nameof(principal));
            if (annualRate < 0)
                throw new ArgumentException("Annual rate cannot be negative", nameof(annualRate));
            if (compoundingFrequency < 1)
                throw new ArgumentException("Compounding frequency must be at least 1", nameof(compoundingFrequency));
            if (years < 0)
                throw new ArgumentException("Years cannot be negative", nameof(years));

            return principal * Math.Pow(1 + annualRate / compoundingFrequency,
                                        compoundingFrequency * years);
        }

        /// <summary>
        /// Compute the interest earned (FutureValue - Principal).
        /// </summary>
        public double InterestEarned(double principal, double annualRate, int compoundingFrequency, double years)
        {
            return FutureValue(principal, annualRate, compoundingFrequency, years) - principal;
        }
    }
}
'@ | Set-Content "$LibDir\CompoundInterestEngine.cs" -Encoding UTF8

# ── 5. CurrencyConverter.cs ───────────────────────────────────────────────────
@'
using System;
using System.Collections.Generic;

namespace FinancialCalc
{
    /// <summary>
    /// Currency converter with a configurable rate table and multi-hop routing.
    /// </summary>
    public class CurrencyConverter
    {
        // rates["USD"]["EUR"] = 0.92  means 1 USD = 0.92 EUR
        private readonly Dictionary<string, Dictionary<string, double>> _rates = new();

        /// <summary>
        /// Register a direct exchange rate from <paramref name="from"/> to <paramref name="to"/>.
        /// Also registers the inverse rate automatically.
        /// </summary>
        public void AddRate(string from, string to, double rate)
        {
            if (string.IsNullOrWhiteSpace(from)) throw new ArgumentException("'from' currency code cannot be empty");
            if (string.IsNullOrWhiteSpace(to))   throw new ArgumentException("'to' currency code cannot be empty");
            if (rate <= 0)                        throw new ArgumentException("Rate must be positive");

            from = from.ToUpperInvariant();
            to   = to.ToUpperInvariant();

            if (!_rates.ContainsKey(from)) _rates[from] = new Dictionary<string, double>();
            if (!_rates.ContainsKey(to))   _rates[to]   = new Dictionary<string, double>();

            _rates[from][to] = rate;
            _rates[to][from] = 1.0 / rate;
        }

        /// <summary>
        /// Convert an amount from one currency to another.
        /// Supports direct and two-hop conversion (via USD as common pivot).
        /// </summary>
        /// <exception cref="InvalidOperationException">If no conversion path is available.</exception>
        public double Convert(double amount, string from, string to)
        {
            if (amount < 0) throw new ArgumentException("Amount cannot be negative");

            from = from?.ToUpperInvariant() ?? throw new ArgumentNullException(nameof(from));
            to   = to?.ToUpperInvariant()   ?? throw new ArgumentNullException(nameof(to));

            if (from == to) return amount;

            // Direct conversion
            if (_rates.TryGetValue(from, out var fromRates) && fromRates.TryGetValue(to, out double rate))
                return amount * rate;

            // Two-hop: try all intermediate currencies
            if (_rates.TryGetValue(from, out var firstHop))
            {
                foreach (var (pivot, r1) in firstHop)
                {
                    if (_rates.TryGetValue(pivot, out var secondHop) && secondHop.TryGetValue(to, out double r2))
                        return amount * r1 * r2;
                }
            }

            throw new InvalidOperationException($"No conversion path found from {from} to {to}");
        }
    }
}
'@ | Set-Content "$LibDir\CurrencyConverter.cs" -Encoding UTF8

# ── 6. Test project file ──────────────────────────────────────────────────────
@'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>disable</ImplicitUsings>
    <RootNamespace>FinancialCalc.Tests</RootNamespace>
    <IsPackable>false</IsPackable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="xunit"                        Version="2.9.0" />
    <PackageReference Include="xunit.runner.visualstudio"    Version="2.8.2">
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
      <PrivateAssets>all</PrivateAssets>
    </PackageReference>
    <PackageReference Include="Microsoft.NET.Test.Sdk"       Version="17.11.1" />
    <PackageReference Include="coverlet.collector"           Version="6.0.2">
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
      <PrivateAssets>all</PrivateAssets>
    </PackageReference>
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\FinancialCalc\FinancialCalc.csproj" />
  </ItemGroup>
</Project>
'@ | Set-Content "$TestDir\FinancialCalc.Tests.csproj" -Encoding UTF8

# ── 7. Empty test file stub — agent must fill this in ─────────────────────────
@'
// FinancialCalcTests.cs
// TODO: Write xUnit tests for LoanCalculator, CompoundInterestEngine, and CurrencyConverter.
// Requirements:
//   - Minimum 3 test methods per class (9 total)
//   - Cover happy path, edge cases, and exception scenarios
//   - Use Assert.Equal, Assert.Throws<>, etc.
//   - Decorate test methods with [Fact] or [Theory]

using System;
using Xunit;
using FinancialCalc;

namespace FinancialCalc.Tests
{
    // Replace this placeholder with real test classes
    public class PlaceholderTests
    {
        [Fact]
        public void Placeholder_AlwaysPasses()
        {
            // Remove this placeholder and add real tests
            Assert.True(true);
        }
    }
}
'@ | Set-Content "$TestDir\FinancialCalcTests.cs" -Encoding UTF8

# ── 8. Build to confirm projects compile ──────────────────────────────────────
$dotnet = Find-DotnetExe
Write-Host "Restoring packages..."
& $dotnet restore "$LibDir\FinancialCalc.csproj" 2>&1 | Out-Null
& $dotnet restore "$TestDir\FinancialCalc.Tests.csproj" 2>&1 | Write-Host

Write-Host "Building library..."
& $dotnet build "$LibDir\FinancialCalc.csproj" --configuration Release 2>&1 | Write-Host

Write-Host "Building test project..."
& $dotnet build "$TestDir\FinancialCalc.Tests.csproj" --configuration Release 2>&1 | Write-Host

# ── 9. Create solution ────────────────────────────────────────────────────────
Push-Location $ProjectDir
& $dotnet new sln --name FinancialCalc --force 2>&1 | Out-Null
& $dotnet sln add "$LibDir\FinancialCalc.csproj" 2>&1 | Out-Null
& $dotnet sln add "$TestDir\FinancialCalc.Tests.csproj" 2>&1 | Out-Null
Pop-Location

# ── 10. Record task-start timestamp ───────────────────────────────────────────
Start-Sleep -Seconds 2
$taskStart = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$taskStart | Set-Content "C:\Users\Docker\qa_test_suite_coverage_start_ts.txt" -Encoding UTF8

Write-Host "Task start timestamp: $taskStart"

# ── 11. Launch VS 2022 ────────────────────────────────────────────────────────
Write-Host "Launching Visual Studio 2022..."
$devenvExe = Find-VS2022Exe
Launch-VS2022Interactive -DevenvExe $devenvExe -SolutionPath $SlnFile -WaitSeconds 25

Write-Host "Dismissing first-run VS dialogs..."
try { Dismiss-VSDialogsBestEffort -Retries 3 -InitialWaitSeconds 5 -BetweenRetriesSeconds 2 }
catch { Write-Host "WARNING: Dialog dismissal: $($_.Exception.Message)" }

Write-Host "=== qa_test_suite_coverage setup complete ==="

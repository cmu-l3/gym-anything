<#
  export_result.ps1 - FinancialCalc QA test suite coverage result export
  Reads test file, counts test methods, runs tests, writes JSON.
#>

. "C:\workspace\scripts\task_utils.ps1"

$TestDir    = "C:\Users\Docker\source\repos\FinancialCalc\src\FinancialCalc.Tests"
$TestFile   = "$TestDir\FinancialCalcTests.cs"
$ResultPath = "C:\Users\Docker\qa_test_suite_coverage_result.json"
$TsFile     = "C:\Users\Docker\qa_test_suite_coverage_start_ts.txt"

Write-Host "=== Exporting qa_test_suite_coverage result ==="

# ── 1. Kill VS ────────────────────────────────────────────────────────────────
Kill-AllVS2022
Start-Sleep -Seconds 3

# ── 2. Read task start timestamp ──────────────────────────────────────────────
$taskStart = 0
if (Test-Path $TsFile) {
    $taskStart = [int](Get-Content $TsFile -Raw).Trim()
}

# ── 3. Read test file ─────────────────────────────────────────────────────────
$testSrc = ""
if (Test-Path $TestFile) {
    $testSrc = Get-Content $TestFile -Raw -Encoding UTF8
}

# ── 4. Check modification time ────────────────────────────────────────────────
$testModified = $false
if (Test-Path $TestFile) {
    $mt = [int][DateTimeOffset]::new((Get-Item $TestFile).LastWriteTimeUtc).ToUnixTimeSeconds()
    $testModified = $mt -gt $taskStart
}

# ── 5. Count [Fact] and [Theory] test methods ─────────────────────────────────
$factCount   = ([regex]::Matches($testSrc, "\[Fact\]")).Count
$theoryCount = ([regex]::Matches($testSrc, "\[Theory\]")).Count
$totalTests  = $factCount + $theoryCount

# ── 6. Check placeholder still present ───────────────────────────────────────
$placeholderPresent = $testSrc -match "Placeholder_AlwaysPasses|Replace this placeholder"

# ── 7. Check coverage of each class ──────────────────────────────────────────
$coversLoan     = $testSrc -match "LoanCalculator"
$coversCompound = $testSrc -match "CompoundInterestEngine"
$coversCurrency = $testSrc -match "CurrencyConverter"

# Check for exception testing patterns
$testsExceptions = $testSrc -match "Assert\.Throws|ArgumentException|InvalidOperationException|ThrowsException"

# Check for edge cases (zero, boundary values)
$testsEdgeCases  = $testSrc -match "0\.0|0,\s*|termMonths.*1\b|years.*0\b|= 0\b"

# ── 8. Build the test project ─────────────────────────────────────────────────
$dotnet = Find-DotnetExe
$buildOut    = & $dotnet build "$TestDir\FinancialCalc.Tests.csproj" --configuration Release 2>&1
$buildStr    = $buildOut -join "`n"
$buildSuccess = $buildStr -match "Build succeeded"
$errMatch    = [regex]::Match($buildStr, "(\d+)\s+Error\(s\)")
$buildErrors = if ($errMatch.Success) { [int]$errMatch.Groups[1].Value } else { 0 }
if (-not $buildSuccess) { $buildErrors = [Math]::Max($buildErrors, 1) }

# ── 9. Run the tests ──────────────────────────────────────────────────────────
$testsPassed  = 0
$testsFailed  = 0
$testsSkipped = 0
$allTestsPassed = $false

if ($buildSuccess) {
    Write-Host "Running tests..."
    $testOut = & $dotnet test "$TestDir\FinancialCalc.Tests.csproj" --configuration Release --no-build 2>&1
    $testStr = $testOut -join "`n"
    Write-Host $testStr

    $passMatch  = [regex]::Match($testStr, "(\d+)\s+passed")
    $failMatch  = [regex]::Match($testStr, "(\d+)\s+failed")
    $skipMatch  = [regex]::Match($testStr, "(\d+)\s+skipped")
    $testsPassed  = if ($passMatch.Success)  { [int]$passMatch.Groups[1].Value }  else { 0 }
    $testsFailed  = if ($failMatch.Success)  { [int]$failMatch.Groups[1].Value }  else { 0 }
    $testsSkipped = if ($skipMatch.Success)  { [int]$skipMatch.Groups[1].Value }  else { 0 }
    $allTestsPassed = ($testsFailed -eq 0) -and ($testsPassed -gt 0)
}

Write-Host "Build: $buildSuccess | Tests passed: $testsPassed | Failed: $testsFailed | Total methods: $totalTests"

# ── 10. Write result JSON ─────────────────────────────────────────────────────
$result = [ordered]@{
    task_start           = $taskStart
    test_file_modified   = $testModified
    total_test_methods   = $totalTests
    fact_count           = $factCount
    theory_count         = $theoryCount
    placeholder_present  = [bool]$placeholderPresent
    covers_loan          = [bool]$coversLoan
    covers_compound      = [bool]$coversCompound
    covers_currency      = [bool]$coversCurrency
    tests_exceptions     = [bool]$testsExceptions
    tests_edge_cases     = [bool]$testsEdgeCases
    build_success        = [bool]$buildSuccess
    build_errors         = $buildErrors
    tests_passed         = $testsPassed
    tests_failed         = $testsFailed
    tests_skipped        = $testsSkipped
    all_tests_passed     = [bool]$allTestsPassed
}

$result | ConvertTo-Json -Depth 5 | Set-Content $ResultPath -Encoding UTF8

Write-Host "Result written to $ResultPath"
Write-Host "=== Export complete ==="

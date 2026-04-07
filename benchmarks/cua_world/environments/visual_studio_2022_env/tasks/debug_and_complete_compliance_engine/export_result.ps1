<#
  export_result.ps1 - ComplianceReporter debug and complete compliance engine result export
  Reads Engine source files, detects bug fixes and stub implementations,
  runs build and tests, checks output files, writes result JSON.
#>

. "C:\workspace\scripts\task_utils.ps1"

$ProjectDir  = "C:\Users\Docker\source\repos\ComplianceReporter"
$EngineDir   = "$ProjectDir\src\ComplianceReporter.Engine"
$TestDir     = "$ProjectDir\tests\ComplianceReporter.Tests"
$ResultPath  = "C:\Users\Docker\debug_and_complete_compliance_engine_result.json"
$TsFile      = "C:\Users\Docker\debug_and_complete_compliance_engine_start_ts.txt"

Write-Host "=== Exporting debug_and_complete_compliance_engine result ==="

# ── 1. Kill VS to flush ───────────────────────────────────────────────────────
Kill-AllVS2022
Start-Sleep -Seconds 3

# ── 2. Read task start timestamp ──────────────────────────────────────────────
$taskStart = 0
if (Test-Path $TsFile) {
    $taskStart = [int](Get-Content $TsFile -Raw).Trim()
}

# ── 3. Read Engine source files ───────────────────────────────────────────────
function Read-Src($path) {
    if (Test-Path $path) { return (Get-Content $path -Raw -Encoding UTF8) }
    return ""
}

$reportGenSrc   = Read-Src "$EngineDir\ReportGenerator.cs"
$statsHelperSrc = Read-Src "$EngineDir\StatisticsHelper.cs"
$reportAggSrc   = Read-Src "$EngineDir\ReportAggregator.cs"

# ── 4. Check modification times ───────────────────────────────────────────────
function Was-Modified($path, $since) {
    if (-not (Test-Path $path)) { return $false }
    $mt = [int][DateTimeOffset]::new((Get-Item $path).LastWriteTimeUtc).ToUnixTimeSeconds()
    return $mt -gt $since
}

$reportGenModified   = Was-Modified "$EngineDir\ReportGenerator.cs"   $taskStart
$statsHelperModified = Was-Modified "$EngineDir\StatisticsHelper.cs"  $taskStart
$reportAggModified   = Was-Modified "$EngineDir\ReportAggregator.cs"  $taskStart
$anyModified         = $reportGenModified -or $statsHelperModified -or $reportAggModified

# ── 5. Bug 1: Severity labels swapped ─────────────────────────────────────────
# Buggy: Grade >= 3 returns "Moderate", Grade >= 2 returns "Severe"
# Fixed: Grade >= 3 returns "Severe", Grade >= 2 returns "Moderate"
# Detect by checking the order of "Severe" and "Moderate" relative to grade checks
$severityBugPresent = $false
$severityBugFixed   = $false
if ($reportGenSrc) {
    # Check if "Moderate" appears in the >= 3 branch (buggy) or "Severe" (fixed)
    $grade3Line = [regex]::Match($reportGenSrc, 'ctcaeGrade\s*>=\s*3\)\s*return\s*"(\w+)"')
    $grade2Line = [regex]::Match($reportGenSrc, 'ctcaeGrade\s*>=\s*2\)\s*return\s*"(\w+)"')
    if ($grade3Line.Success -and $grade2Line.Success) {
        $g3Label = $grade3Line.Groups[1].Value
        $g2Label = $grade2Line.Groups[1].Value
        $severityBugPresent = ($g3Label -eq "Moderate") -and ($g2Label -eq "Severe")
        $severityBugFixed   = ($g3Label -eq "Severe") -and ($g2Label -eq "Moderate")
    }
}

# ── 6. Bug 2: Date subtraction reversed ───────────────────────────────────────
# Buggy:  (enrollmentDate - eventDate).Days
# Fixed:  (eventDate - enrollmentDate).Days
$dateBugPresent = $reportGenSrc -match "enrollmentDate\s*-\s*eventDate"
$dateBugFixed   = $reportGenSrc -match "eventDate\s*-\s*enrollmentDate"

# ── 7. Bug 3: Integer division ─────────────────────────────────────────────────
# Buggy:  return eventCount / totalPatients;  (int / int = int)
# Fixed:  return (double)eventCount / totalPatients; or similar cast
$intDivBugPresent = ($statsHelperSrc -match "return\s+eventCount\s*/\s*totalPatients\s*;") -and
                    -not ($statsHelperSrc -match "\(double\)")
$intDivBugFixed   = $statsHelperSrc -match "\(double\)\s*eventCount|\(double\)\s*totalPatients|eventCount\s*\*\s*1\.0|1\.0\s*\*\s*eventCount"

# ── 8. Stub 1: Wilson Score Interval ──────────────────────────────────────────
$wilsonIsStub   = $reportAggSrc -match "throw\s+new\s+NotImplementedException" -and
                  $reportAggSrc -match "CalculateWilsonScoreInterval"
$wilsonImplHasSqrt = $reportAggSrc -match "Math\.Sqrt"
$wilsonImplHasFormula = $reportAggSrc -match "zScore\s*\*\s*zScore|z\s*\*\s*z|Math\.Pow.*zScore"
# Check that the stub is replaced (no NotImplementedException in the Wilson method area)
$wilsonStubRemoved = -not ($reportAggSrc -match "CalculateWilsonScoreInterval[\s\S]{0,300}NotImplementedException")

# ── 9. Stub 2: Expedited Flags ────────────────────────────────────────────────
$flagsIsStub   = $reportAggSrc -match "DetectExpeditedReportingFlags[\s\S]{0,300}NotImplementedException"
$flagsStubRemoved = -not $flagsIsStub
$flagsHasFilter = $reportAggSrc -match "CtcaeGrade\s*>=\s*4|Grade\s*>=\s*4" -and
                  ($reportAggSrc -match '"Death"' -or $reportAggSrc -match '"Life-Threatening"') -and
                  $reportAggSrc -match "15|fifteen"

# ── 10. Build ─────────────────────────────────────────────────────────────────
$dotnet = Find-DotnetExe
$oldEAP = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'

$buildOut = & $dotnet build "$ProjectDir\ComplianceReporter.sln" --configuration Release 2>&1
$buildStr = $buildOut -join "`n"
$buildSuccess = $buildStr -match "Build succeeded"
$errMatch = [regex]::Match($buildStr, "(\d+)\s+Error\(s\)")
$buildErrors = if ($errMatch.Success) { [int]$errMatch.Groups[1].Value } else { 0 }
if (-not $buildSuccess) { $buildErrors = [Math]::Max($buildErrors, 1) }

# ── 11. Run tests ─────────────────────────────────────────────────────────────
$testsPassed  = 0
$testsFailed  = 0
$allTestsPassed = $false

if ($buildSuccess) {
    Write-Host "Running tests..."
    $testOut = & $dotnet test "$TestDir\ComplianceReporter.Tests.csproj" --no-build --configuration Release 2>&1
    $testStr = $testOut -join "`n"
    Write-Host $testStr

    $passMatch = [regex]::Match($testStr, "Passed:\s+(\d+)")
    $failMatch = [regex]::Match($testStr, "Failed:\s+(\d+)")
    # Fallback: also try "X passed" format (older dotnet test versions)
    if (-not $passMatch.Success) { $passMatch = [regex]::Match($testStr, "(\d+)\s+passed") }
    if (-not $failMatch.Success) { $failMatch = [regex]::Match($testStr, "(\d+)\s+failed") }
    $testsPassed  = if ($passMatch.Success)  { [int]$passMatch.Groups[1].Value }  else { 0 }
    $testsFailed  = if ($failMatch.Success)  { [int]$failMatch.Groups[1].Value }  else { 0 }
    $allTestsPassed = ($testsFailed -eq 0) -and ($testsPassed -ge 12)
}

$ErrorActionPreference = $oldEAP

# ── 12. Check output files ────────────────────────────────────────────────────
$complianceReportExists = Test-Path "C:\Users\Docker\Documents\compliance_report.txt"
$debugReportExists      = Test-Path "C:\Users\Docker\Documents\debug_report.txt"

$complianceReportContent = ""
$debugReportContent      = ""
if ($complianceReportExists) {
    $complianceReportContent = Get-Content "C:\Users\Docker\Documents\compliance_report.txt" -Raw -Encoding UTF8
}
if ($debugReportExists) {
    $debugReportContent = Get-Content "C:\Users\Docker\Documents\debug_report.txt" -Raw -Encoding UTF8
}

# Check compliance report has key content
$reportHasSeverity  = $complianceReportContent -match "Severity Classification"
$reportHasExpedited = $complianceReportContent -match "Expedited Reporting"
$reportHasWilson    = $complianceReportContent -match "95%.*CI|confidence"

# Check debug report mentions bugs
$debugMentionsSeverity = $debugReportContent -match "severity|Severe|Moderate|swap|label"
$debugMentionsDate     = $debugReportContent -match "date|onset|reverse|subtract"
$debugMentionsDivision = $debugReportContent -match "integer|division|double|cast|truncat"

Write-Host "Build: $buildSuccess | Tests: $testsPassed passed, $testsFailed failed"
Write-Host "Bug1 fixed: $severityBugFixed | Bug2 fixed: $dateBugFixed | Bug3 fixed: $intDivBugFixed"
Write-Host "Wilson stub removed: $wilsonStubRemoved | Flags stub removed: $flagsStubRemoved"
Write-Host "Compliance report: $complianceReportExists | Debug report: $debugReportExists"

# ── 13. Write result JSON ─────────────────────────────────────────────────────
$result = [ordered]@{
    task_start               = $taskStart
    any_file_modified        = $anyModified
    report_gen_modified      = $reportGenModified
    stats_helper_modified    = $statsHelperModified
    report_agg_modified      = $reportAggModified
    severity_bug_present     = [bool]$severityBugPresent
    severity_bug_fixed       = [bool]$severityBugFixed
    date_bug_present         = [bool]$dateBugPresent
    date_bug_fixed           = [bool]$dateBugFixed
    int_div_bug_present      = [bool]$intDivBugPresent
    int_div_bug_fixed        = [bool]$intDivBugFixed
    wilson_stub_removed      = [bool]$wilsonStubRemoved
    wilson_has_sqrt          = [bool]$wilsonImplHasSqrt
    wilson_has_formula       = [bool]$wilsonImplHasFormula
    flags_stub_removed       = [bool]$flagsStubRemoved
    flags_has_filter         = [bool]$flagsHasFilter
    build_success            = [bool]$buildSuccess
    build_errors             = $buildErrors
    tests_passed             = $testsPassed
    tests_failed             = $testsFailed
    all_tests_passed         = [bool]$allTestsPassed
    compliance_report_exists = [bool]$complianceReportExists
    report_has_severity      = [bool]$reportHasSeverity
    report_has_expedited     = [bool]$reportHasExpedited
    report_has_wilson        = [bool]$reportHasWilson
    debug_report_exists      = [bool]$debugReportExists
    debug_mentions_severity  = [bool]$debugMentionsSeverity
    debug_mentions_date      = [bool]$debugMentionsDate
    debug_mentions_division  = [bool]$debugMentionsDivision
}

$result | ConvertTo-Json -Depth 5 | Set-Content $ResultPath -Encoding UTF8

Write-Host "Result written to $ResultPath"
Write-Host "=== Export complete ==="

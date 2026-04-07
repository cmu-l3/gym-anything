<#
  setup_task.ps1 - ComplianceReporter debug and complete compliance engine task
  Creates a multi-project .NET 8 solution with 3 injected bugs and 2 stubs.
  Agent must run tests, debug failures, fix bugs, implement stubs, run the app.
#>

. "C:\workspace\scripts\task_utils.ps1"

$ProjectDir = "C:\Users\Docker\source\repos\ComplianceReporter"
$EngineDir  = "$ProjectDir\src\ComplianceReporter.Engine"
$AppDir     = "$ProjectDir\src\ComplianceReporter.App"
$TestDir    = "$ProjectDir\tests\ComplianceReporter.Tests"
$SlnFile    = "$ProjectDir\ComplianceReporter.sln"

Write-Host "=== Setting up debug_and_complete_compliance_engine task ==="

# ── 1. Clean prior run ────────────────────────────────────────────────────────
Kill-AllVS2022
Start-Sleep -Seconds 2

if (Test-Path $ProjectDir) {
    Remove-Item $ProjectDir -Recurse -Force
}

# Delete stale output files BEFORE recording timestamp
Remove-Item "C:\Users\Docker\Documents\compliance_report.txt" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Users\Docker\Documents\debug_report.txt" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Users\Docker\debug_and_complete_compliance_engine_result.json" -Force -ErrorAction SilentlyContinue

# Create directory structure
New-Item -ItemType Directory -Path "$EngineDir\Models" -Force | Out-Null
New-Item -ItemType Directory -Path $AppDir              -Force | Out-Null
New-Item -ItemType Directory -Path $TestDir             -Force | Out-Null

# ── 2. Engine project file ────────────────────────────────────────────────────
@'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <RootNamespace>ComplianceReporter.Engine</RootNamespace>
    <AssemblyName>ComplianceReporter.Engine</AssemblyName>
  </PropertyGroup>
</Project>
'@ | Set-Content "$EngineDir\ComplianceReporter.Engine.csproj" -Encoding UTF8

# ── 3. AdverseEvent model ─────────────────────────────────────────────────────
@'
namespace ComplianceReporter.Engine.Models;

/// <summary>
/// Represents a single adverse event record from a clinical trial,
/// aligned with FDA MedWatch / ICH E2B reporting fields.
/// </summary>
public class AdverseEvent
{
    public string EventId { get; set; } = "";
    public string PatientId { get; set; } = "";
    public string PreferredTerm { get; set; } = "";
    public int CtcaeGrade { get; set; }
    public string Outcome { get; set; } = "";
    public DateTime EnrollmentDate { get; set; }
    public DateTime EventDate { get; set; }
    public string StudyId { get; set; } = "";
}
'@ | Set-Content "$EngineDir\Models\AdverseEvent.cs" -Encoding UTF8

# ── 4. ReportGenerator.cs — BUG 1 (severity labels swapped) + BUG 2 (date reversal) ──
@'
using ComplianceReporter.Engine.Models;

namespace ComplianceReporter.Engine;

/// <summary>
/// Generates classification and temporal analysis for adverse event reports.
/// </summary>
public class ReportGenerator
{
    /// <summary>
    /// Classify adverse event severity per CTCAE v5.0 grading scale.
    /// Grade 1: Mild, Grade 2: Moderate, Grade 3: Severe,
    /// Grade 4: Life-Threatening, Grade 5: Fatal.
    /// </summary>
    public static string ClassifySeverity(int ctcaeGrade)
    {
        if (ctcaeGrade >= 5) return "Fatal";
        if (ctcaeGrade >= 4) return "Life-Threatening";
        if (ctcaeGrade >= 3) return "Moderate";
        if (ctcaeGrade >= 2) return "Severe";
        return "Mild";
    }

    /// <summary>
    /// Calculate the number of days between patient enrollment and adverse event onset.
    /// A positive value indicates the event occurred after enrollment.
    /// </summary>
    public static int CalculateOnsetDays(DateTime enrollmentDate, DateTime eventDate)
    {
        return (enrollmentDate - eventDate).Days;
    }
}
'@ | Set-Content "$EngineDir\ReportGenerator.cs" -Encoding UTF8

# ── 5. StatisticsHelper.cs — BUG 3 (integer division) ─────────────────────────
@'
namespace ComplianceReporter.Engine;

/// <summary>
/// Statistical utility methods for adverse event rate analysis.
/// </summary>
public static class StatisticsHelper
{
    /// <summary>
    /// Calculate the event rate as a proportion of total patients.
    /// Returns eventCount divided by totalPatients as a decimal fraction.
    /// </summary>
    /// <exception cref="DivideByZeroException">Thrown when totalPatients is zero.</exception>
    public static double CalculateEventRate(int eventCount, int totalPatients)
    {
        if (totalPatients == 0)
            throw new DivideByZeroException("Total patients cannot be zero.");
        return eventCount / totalPatients;
    }
}
'@ | Set-Content "$EngineDir\StatisticsHelper.cs" -Encoding UTF8

# ── 6. ReportAggregator.cs — STUB 1 (Wilson CI) + STUB 2 (expedited flags) ───
@'
using ComplianceReporter.Engine.Models;

namespace ComplianceReporter.Engine;

/// <summary>
/// Aggregation and regulatory analysis methods for compliance reporting.
/// </summary>
public static class ReportAggregator
{
    /// <summary>
    /// Calculates the Wilson score confidence interval for a binomial proportion.
    /// Formula: (p + z^2/2n +/- z * sqrt(p*(1-p)/n + z^2/4n^2)) / (1 + z^2/n)
    /// where p = successes/trials, n = trials, z = zScore.
    /// </summary>
    /// <param name="successes">Number of successes (events of interest)</param>
    /// <param name="trials">Total number of trials</param>
    /// <param name="zScore">Z-score for desired confidence level (e.g., 1.96 for 95%)</param>
    /// <returns>A tuple of (lower bound, upper bound) for the confidence interval</returns>
    public static (double lower, double upper) CalculateWilsonScoreInterval(
        int successes, int trials, double zScore)
    {
        throw new NotImplementedException();
    }

    /// <summary>
    /// Identifies adverse events requiring FDA 15-day expedited reporting.
    /// An event requires expedited reporting when ALL of the following hold:
    ///   - CTCAE Grade is 4 or higher
    ///   - Outcome is "Death" or "Life-Threatening"
    ///   - Event onset occurred within 15 days of enrollment
    /// </summary>
    /// <param name="events">List of adverse events to evaluate</param>
    /// <returns>Filtered list containing only events that require expedited reporting</returns>
    public static List<AdverseEvent> DetectExpeditedReportingFlags(
        List<AdverseEvent> events)
    {
        throw new NotImplementedException();
    }
}
'@ | Set-Content "$EngineDir\ReportAggregator.cs" -Encoding UTF8

# ── 7. App project file ───────────────────────────────────────────────────────
@'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <OutputType>Exe</OutputType>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <RootNamespace>ComplianceReporter.App</RootNamespace>
    <AssemblyName>ComplianceReporter.App</AssemblyName>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="..\ComplianceReporter.Engine\ComplianceReporter.Engine.csproj" />
  </ItemGroup>
</Project>
'@ | Set-Content "$AppDir\ComplianceReporter.App.csproj" -Encoding UTF8

# ── 8. App Program.cs ─────────────────────────────────────────────────────────
@'
using System.Globalization;
using ComplianceReporter.Engine;
using ComplianceReporter.Engine.Models;

string csvPath = @"C:\Users\Docker\source\repos\ComplianceReporter\adverse_events.csv";
string reportPath = @"C:\Users\Docker\Documents\compliance_report.txt";

// ── Parse CSV ──
var events = new List<AdverseEvent>();
foreach (var line in File.ReadLines(csvPath).Skip(1))
{
    var parts = line.Split(',');
    if (parts.Length < 8) continue;
    events.Add(new AdverseEvent
    {
        EventId = parts[0].Trim(),
        PatientId = parts[1].Trim(),
        PreferredTerm = parts[2].Trim(),
        CtcaeGrade = int.Parse(parts[3].Trim()),
        Outcome = parts[4].Trim(),
        EnrollmentDate = DateTime.Parse(parts[5].Trim(), CultureInfo.InvariantCulture),
        EventDate = DateTime.Parse(parts[6].Trim(), CultureInfo.InvariantCulture),
        StudyId = parts[7].Trim()
    });
}

// ── Generate Report ──
var lines = new List<string>();
lines.Add("=== Clinical Trial Compliance Report ===");
lines.Add($"Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
lines.Add($"Total Adverse Events: {events.Count}");
lines.Add("");

// Severity breakdown
lines.Add("--- Severity Classification ---");
var severityGroups = events
    .GroupBy(e => ReportGenerator.ClassifySeverity(e.CtcaeGrade))
    .OrderBy(g => g.Key);
foreach (var group in severityGroups)
{
    lines.Add($"  {group.Key}: {group.Count()} events");
}
lines.Add("");

// Event rates
lines.Add("--- Event Rates by Severity ---");
int totalPatients = events.Select(e => e.PatientId).Distinct().Count();
foreach (var group in severityGroups)
{
    double rate = StatisticsHelper.CalculateEventRate(group.Count(), totalPatients);
    lines.Add($"  {group.Key} rate: {rate:F4} ({group.Count()}/{totalPatients})");
}
lines.Add("");

// Expedited reporting flags
lines.Add("--- Expedited Reporting Flags (FDA 15-day rule) ---");
var flagged = ReportAggregator.DetectExpeditedReportingFlags(events);
if (flagged.Count == 0)
{
    lines.Add("  No events require expedited reporting.");
}
else
{
    foreach (var e in flagged)
    {
        int onsetDays = ReportGenerator.CalculateOnsetDays(e.EnrollmentDate, e.EventDate);
        lines.Add($"  {e.EventId}: {e.PreferredTerm} (Grade {e.CtcaeGrade}, {e.Outcome}, onset day {onsetDays})");
    }
}
lines.Add("");

// Wilson confidence interval for SAE rate
int saeCount = events.Count(e => e.CtcaeGrade >= 3);
lines.Add("--- Serious Adverse Event (Grade >= 3) Analysis ---");
lines.Add($"  SAE Count: {saeCount} of {events.Count} total events");
var (lower, upper) = ReportAggregator.CalculateWilsonScoreInterval(saeCount, events.Count, 1.96);
lines.Add($"  SAE Rate: {(double)saeCount / events.Count:F4} [95% CI: {lower:F4}, {upper:F4}]");
lines.Add("");
lines.Add("=== End of Report ===");

// Write report
Directory.CreateDirectory(Path.GetDirectoryName(reportPath)!);
File.WriteAllLines(reportPath, lines);

Console.WriteLine($"Compliance report written to: {reportPath}");
Console.WriteLine($"Total events processed: {events.Count}");
Console.WriteLine($"Expedited flags: {flagged.Count}");
'@ | Set-Content "$AppDir\Program.cs" -Encoding UTF8

# ── 9. Test project file ──────────────────────────────────────────────────────
@'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <RootNamespace>ComplianceReporter.Tests</RootNamespace>
    <IsPackable>false</IsPackable>
    <IsTestProject>true</IsTestProject>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.11.1" />
    <PackageReference Include="xunit" Version="2.9.0" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.8.2">
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
      <PrivateAssets>all</PrivateAssets>
    </PackageReference>
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\ComplianceReporter.Engine\ComplianceReporter.Engine.csproj" />
  </ItemGroup>
</Project>
'@ | Set-Content "$TestDir\ComplianceReporter.Tests.csproj" -Encoding UTF8

# ── 10. Test file — ALL TESTS ARE CORRECT, agent must NOT modify this file ────
@'
using Xunit;
using ComplianceReporter.Engine;
using ComplianceReporter.Engine.Models;

namespace ComplianceReporter.Tests;

/// <summary>
/// Unit tests for the ComplianceReporter.Engine library.
/// All tests in this file are correct — fix the Engine code, not the tests.
/// </summary>
public class EngineTests
{
    // ── Severity Classification ──────────────────────────────────────────

    [Fact]
    public void ClassifySeverity_Grade1_ReturnsMild()
    {
        Assert.Equal("Mild", ReportGenerator.ClassifySeverity(1));
    }

    [Fact]
    public void ClassifySeverity_Grade3_ReturnsSevere()
    {
        Assert.Equal("Severe", ReportGenerator.ClassifySeverity(3));
    }

    [Fact]
    public void ClassifySeverity_Grade4_ReturnsLifeThreatening()
    {
        Assert.Equal("Life-Threatening", ReportGenerator.ClassifySeverity(4));
    }

    [Fact]
    public void ClassifySeverity_Grade5_ReturnsFatal()
    {
        Assert.Equal("Fatal", ReportGenerator.ClassifySeverity(5));
    }

    // ── Onset Days Calculation ───────────────────────────────────────────

    [Fact]
    public void CalculateOnsetDays_14DaysApart_Returns14()
    {
        var enrollment = new DateTime(2024, 1, 15);
        var eventDate = new DateTime(2024, 1, 29);
        Assert.Equal(14, ReportGenerator.CalculateOnsetDays(enrollment, eventDate));
    }

    [Fact]
    public void CalculateOnsetDays_SameDay_ReturnsZero()
    {
        var date = new DateTime(2024, 3, 1);
        Assert.Equal(0, ReportGenerator.CalculateOnsetDays(date, date));
    }

    // ── Event Rate Calculation ───────────────────────────────────────────

    [Fact]
    public void CalculateEventRate_15of100_Returns0point15()
    {
        Assert.Equal(0.15, StatisticsHelper.CalculateEventRate(15, 100), 3);
    }

    [Fact]
    public void CalculateEventRate_EvenDivision_Returns2()
    {
        Assert.Equal(2.0, StatisticsHelper.CalculateEventRate(100, 50), 3);
    }

    // ── Wilson Score Confidence Interval ─────────────────────────────────

    [Fact]
    public void WilsonCI_50of200_ReturnsExpected()
    {
        var (lower, upper) = ReportAggregator.CalculateWilsonScoreInterval(50, 200, 1.96);
        Assert.InRange(lower, 0.19, 0.20);
        Assert.InRange(upper, 0.31, 0.32);
    }

    [Fact]
    public void WilsonCI_AllSuccesses_UpperBoundIsOne()
    {
        var (lower, upper) = ReportAggregator.CalculateWilsonScoreInterval(100, 100, 1.96);
        Assert.InRange(lower, 0.96, 0.97);
        Assert.InRange(upper, 0.99, 1.01);
    }

    // ── Expedited Reporting Flags ────────────────────────────────────────

    [Fact]
    public void ExpeditedFlags_MixedEvents_FiltersCorrectly()
    {
        var events = new List<AdverseEvent>
        {
            new() { EventId = "AE-001", CtcaeGrade = 5, Outcome = "Death",
                     EnrollmentDate = new DateTime(2024, 1, 1),
                     EventDate = new DateTime(2024, 1, 8) },
            new() { EventId = "AE-002", CtcaeGrade = 4, Outcome = "Life-Threatening",
                     EnrollmentDate = new DateTime(2024, 2, 1),
                     EventDate = new DateTime(2024, 2, 10) },
            new() { EventId = "AE-003", CtcaeGrade = 3, Outcome = "Death",
                     EnrollmentDate = new DateTime(2024, 3, 1),
                     EventDate = new DateTime(2024, 3, 5) },
            new() { EventId = "AE-004", CtcaeGrade = 4, Outcome = "Death",
                     EnrollmentDate = new DateTime(2024, 4, 1),
                     EventDate = new DateTime(2024, 5, 1) },
            new() { EventId = "AE-005", CtcaeGrade = 2, Outcome = "Recovered",
                     EnrollmentDate = new DateTime(2024, 5, 1),
                     EventDate = new DateTime(2024, 5, 3) },
        };

        var flagged = ReportAggregator.DetectExpeditedReportingFlags(events);

        Assert.Equal(2, flagged.Count);
        Assert.Contains(flagged, e => e.EventId == "AE-001");
        Assert.Contains(flagged, e => e.EventId == "AE-002");
    }

    [Fact]
    public void ExpeditedFlags_NoneQualify_ReturnsEmpty()
    {
        var events = new List<AdverseEvent>
        {
            new() { EventId = "AE-010", CtcaeGrade = 2, Outcome = "Recovered",
                     EnrollmentDate = new DateTime(2024, 1, 1),
                     EventDate = new DateTime(2024, 1, 5) },
            new() { EventId = "AE-011", CtcaeGrade = 4, Outcome = "Recovered",
                     EnrollmentDate = new DateTime(2024, 2, 1),
                     EventDate = new DateTime(2024, 2, 5) },
        };

        var flagged = ReportAggregator.DetectExpeditedReportingFlags(events);

        Assert.Empty(flagged);
    }
}
'@ | Set-Content "$TestDir\EngineTests.cs" -Encoding UTF8

# ── 11. Adverse events CSV dataset ────────────────────────────────────────────
@'
EventId,PatientId,PreferredTerm,CtcaeGrade,Outcome,EnrollmentDate,EventDate,StudyId
AE-2024-00001,SUBJ-0042,Neutropenia,3,Recovered,2024-01-15,2024-02-12,TRIAL-ONCO-003
AE-2024-00002,SUBJ-0108,Cardiac Arrest,5,Death,2024-03-01,2024-03-08,TRIAL-ONCO-003
AE-2024-00003,SUBJ-0071,Anaphylaxis,4,Life-Threatening,2024-02-20,2024-03-01,TRIAL-ONCO-003
AE-2024-00004,SUBJ-0042,Nausea,1,Recovered,2024-01-15,2024-01-18,TRIAL-ONCO-003
AE-2024-00005,SUBJ-0023,Peripheral Neuropathy,2,Not Recovered,2024-04-10,2024-05-22,TRIAL-ONCO-003
AE-2024-00006,SUBJ-0089,Febrile Neutropenia,4,Death,2024-05-01,2024-05-09,TRIAL-ONCO-003
AE-2024-00007,SUBJ-0156,Tumor Lysis Syndrome,3,Recovered,2024-06-15,2024-07-01,TRIAL-ONCO-003
AE-2024-00008,SUBJ-0023,Thrombocytopenia,2,Recovered,2024-04-10,2024-04-25,TRIAL-ONCO-003
AE-2024-00009,SUBJ-0201,Rash Maculopapular,1,Recovered,2024-07-01,2024-07-10,TRIAL-ONCO-003
AE-2024-00010,SUBJ-0089,Hepatotoxicity,3,Not Recovered,2024-05-01,2024-06-15,TRIAL-ONCO-003
AE-2024-00011,SUBJ-0134,Diarrhea,1,Recovered,2024-08-01,2024-08-05,TRIAL-ONCO-003
AE-2024-00012,SUBJ-0156,Pneumonitis,3,Recovered,2024-06-15,2024-06-28,TRIAL-ONCO-003
AE-2024-00013,SUBJ-0042,Fatigue,1,Recovered,2024-01-15,2024-02-01,TRIAL-ONCO-003
AE-2024-00014,SUBJ-0201,Hypertension,2,Not Recovered,2024-07-01,2024-08-15,TRIAL-ONCO-003
AE-2024-00015,SUBJ-0267,Myocardial Infarction,5,Death,2024-09-01,2024-09-12,TRIAL-ONCO-003
AE-2024-00016,SUBJ-0267,Alopecia,1,Recovered,2024-09-01,2024-09-20,TRIAL-ONCO-003
AE-2024-00017,SUBJ-0312,Dyspnea,2,Recovered,2024-10-01,2024-10-18,TRIAL-ONCO-003
AE-2024-00018,SUBJ-0134,Mucositis,2,Recovered,2024-08-01,2024-08-12,TRIAL-ONCO-003
AE-2024-00019,SUBJ-0312,Sepsis,4,Life-Threatening,2024-10-01,2024-10-05,TRIAL-ONCO-003
AE-2024-00020,SUBJ-0378,Anemia,2,Recovered,2024-11-01,2024-11-20,TRIAL-ONCO-003
AE-2024-00021,SUBJ-0378,Pulmonary Embolism,4,Life-Threatening,2024-11-01,2024-11-25,TRIAL-ONCO-003
AE-2024-00022,SUBJ-0401,Vomiting,1,Recovered,2024-12-01,2024-12-03,TRIAL-ONCO-003
AE-2024-00023,SUBJ-0401,Colitis,3,Recovered,2024-12-01,2024-12-20,TRIAL-ONCO-003
AE-2024-00024,SUBJ-0445,Infusion Related Reaction,2,Recovered,2025-01-10,2025-01-11,TRIAL-ONCO-003
AE-2024-00025,SUBJ-0445,Cerebrovascular Accident,4,Death,2025-01-10,2025-01-20,TRIAL-ONCO-003
'@ | Set-Content "$ProjectDir\adverse_events.csv" -Encoding UTF8

# ── 12. NuGet restore and build to verify compilation ─────────────────────────
$dotnet = Find-DotnetExe
$ErrorActionPreference = 'SilentlyContinue'

Write-Host "Restoring NuGet packages..."
& $dotnet restore "$EngineDir\ComplianceReporter.Engine.csproj" 2>&1 | Out-Null
& $dotnet restore "$AppDir\ComplianceReporter.App.csproj" 2>&1 | Out-Null
& $dotnet restore "$TestDir\ComplianceReporter.Tests.csproj" 2>&1 | Out-Null

Write-Host "Building Engine library..."
& $dotnet build "$EngineDir\ComplianceReporter.Engine.csproj" --configuration Release 2>&1 | Out-Null

Write-Host "Building App project..."
& $dotnet build "$AppDir\ComplianceReporter.App.csproj" --configuration Release 2>&1 | Out-Null

Write-Host "Building Test project..."
& $dotnet build "$TestDir\ComplianceReporter.Tests.csproj" --configuration Release 2>&1 | Out-Null

# ── 13. Create solution ───────────────────────────────────────────────────────
Push-Location $ProjectDir
& $dotnet new sln --name ComplianceReporter --force 2>&1 | Out-Null
# App first so VS selects it as startup project
& $dotnet sln add "$AppDir\ComplianceReporter.App.csproj" 2>&1 | Out-Null
& $dotnet sln add "$EngineDir\ComplianceReporter.Engine.csproj" 2>&1 | Out-Null
& $dotnet sln add "$TestDir\ComplianceReporter.Tests.csproj" 2>&1 | Out-Null
Pop-Location

# ── 14. Record task-start timestamp AFTER all setup ───────────────────────────
Start-Sleep -Seconds 2
$taskStart = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$taskStart | Set-Content "C:\Users\Docker\debug_and_complete_compliance_engine_start_ts.txt" -Encoding UTF8

Write-Host "Task start timestamp recorded: $taskStart"

# ── 16. Launch VS 2022 with the solution ──────────────────────────────────────
Write-Host "Launching Visual Studio 2022..."
$devenvExe = Find-VS2022Exe
Launch-VS2022Interactive -DevenvExe $devenvExe -SolutionPath $SlnFile -WaitSeconds 25

Write-Host "Dismissing first-run VS dialogs..."
try { Dismiss-VSDialogsBestEffort -Retries 3 -InitialWaitSeconds 5 -BetweenRetriesSeconds 2 }
catch { Write-Host "WARNING: Dialog dismissal: $($_.Exception.Message)" }

Write-Host "=== debug_and_complete_compliance_engine setup complete ==="

# Setup: hepatitis_b_surveillance_form_entry
# Prepares environment for 3-module workflow: MakeView -> Enter -> Analysis
# Does NOT pre-create the project - the agent must do all 3 steps from scratch

. "C:\workspace\scripts\task_utils.ps1"

Write-Host "=== Setting up hepatitis_b_surveillance_form_entry ==="

$edgeKiller = Start-EdgeKillerTask
Stop-EpiInfo
Close-Browsers
Start-Sleep -Seconds 2

# STEP 1: Delete stale output files and any pre-existing HepB project (BEFORE timestamp)
$filesToClean = @(
    "C:\Users\Docker\Documents\HepBSurveillance.prj",
    "C:\Users\Docker\Documents\HepBSurveillance.mdb",
    "C:\Users\Docker\Documents\HepBSurveillance.pgm",
    "C:\Users\Docker\hepb_analysis.html",
    "C:\Users\Docker\hepb_analysis.htm"
)
foreach ($f in $filesToClean) {
    Remove-Item $f -Force -ErrorAction SilentlyContinue
}

# Ensure the Documents directory exists
if (-not (Test-Path "C:\Users\Docker\Documents")) {
    New-Item -ItemType Directory -Path "C:\Users\Docker\Documents" -Force | Out-Null
}

# STEP 2: Record task start timestamp AFTER cleanup
$ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_hepb.txt" -Encoding ASCII -Force
Write-Host "Task start timestamp: $ts"

# STEP 3: Launch the main Epi Info 7 launcher (not a specific module)
# Agent must navigate from launcher to MakeView themselves
Write-Host "Launching Epi Info 7 main application..."
$launcher = Find-EpiInfoLauncher
if ($launcher) {
    # Launch via schtasks /IT to get desktop session
    $vbs = @"
Set oShell = CreateObject("WScript.Shell")
oShell.Run "$launcher", 1, False
"@
    $vbs | Out-File -FilePath "C:\Windows\Temp\launch_epiinfo.vbs" -Encoding ASCII -Force
    schtasks /Create /TN "LaunchEpiInfo" /TR "cscript C:\Windows\Temp\launch_epiinfo.vbs" /SC ONCE /SD 01/01/2099 /ST 00:00 /RL HIGHEST /IT /F 2>&1 | Out-Null
    schtasks /Run /TN "LaunchEpiInfo" 2>&1 | Out-Null
    Write-Host "Epi Info 7 launcher started."
    Start-Sleep -Seconds 15

    # Dismiss any dialogs
    Dismiss-EpiInfoDialogs -Retries 5 -WaitSeconds 3
} else {
    Write-Host "WARNING: Could not find Epi Info 7 launcher. Trying Analysis.exe as fallback..."
    Launch-EpiInfoModuleInteractive -ModuleExe "Analysis.exe" -WaitSeconds 15
    Dismiss-EpiInfoDialogs -Retries 3 -WaitSeconds 2
}

Stop-EdgeKillerTask -KillerInfo $edgeKiller

Write-Host "=== Setup Complete: hepatitis_b_surveillance_form_entry ==="
Write-Host ""
Write-Host "Agent workflow:"
Write-Host "1. MakeView: Create project HepBSurveillance.prj at C:\Users\Docker\Documents\"
Write-Host "   Form: CaseReport with 11 fields:"
Write-Host "   CaseID (Text 10), ReportDate (Date), County (Text 30), Sex (Text 10),"
Write-Host "   AgeAtDiagnosis (Number), HBsAg_Positive (Yes/No), Anti_HBc_Positive (Yes/No),"
Write-Host "   HBeAg_Status (Text 10), SourceOfInfection (Text 50),"
Write-Host "   VaccinationStatus (Text 20), ClinicalStatus (Text 20)"
Write-Host ""
Write-Host "2. Enter: Open HepBSurveillance.prj and enter 8 Hepatitis B case records"
Write-Host "   Vary: County, Sex, Age, SourceOfInfection, VaccinationStatus, ClinicalStatus"
Write-Host ""
Write-Host "3. Analysis: READ HepBSurveillance.mdb:CaseReport"
Write-Host "   ROUTEOUT C:\Users\Docker\hepb_analysis.html REPLACE"
Write-Host "   FREQ Sex, County, SourceOfInfection, VaccinationStatus, ClinicalStatus"
Write-Host "   MEANS AgeAtDiagnosis"
Write-Host "   ROUTEOUT"

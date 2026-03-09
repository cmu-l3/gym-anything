# Setup script for create_class_file task.
# Opens VS 2022 with the InventoryManager solution. Ensures no InventoryReport.cs exists.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_create_class_file.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up create_class_file task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    Kill-AllVS2022

    # Ensure the InventoryManager project exists
    $projDir = "C:\Users\Docker\source\repos\InventoryManager"
    if (-not (Test-Path "$projDir\InventoryManager.csproj")) {
        throw "InventoryManager project not found at: $projDir"
    }

    # Remove InventoryReport.cs if it already exists (ensure clean start)
    $reportFile = "$projDir\InventoryReport.cs"
    if (Test-Path $reportFile) {
        Remove-Item $reportFile -Force
        Write-Host "Removed existing InventoryReport.cs."
    }

    # Clean build output
    Remove-Item "$projDir\bin" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$projDir\obj" -Recurse -Force -ErrorAction SilentlyContinue

    # Ensure .sln exists
    $slnPath = "$projDir\InventoryManager.sln"
    if (-not (Test-Path $slnPath)) {
        $dotnet = Find-DotnetExe
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        & $dotnet new sln -n InventoryManager -o $projDir --force 2>&1 | Out-Null
        & $dotnet sln "$projDir\InventoryManager.sln" add "$projDir\InventoryManager.csproj" 2>&1 | Out-Null
        $ErrorActionPreference = $prevEAP
    }

    # Launch VS with the solution
    $devenvExe = Find-VS2022Exe
    Write-Host "VS executable: $devenvExe"
    Write-Host "Launching VS with InventoryManager.sln..."
    Launch-VS2022Interactive -DevenvExe $devenvExe -SolutionPath $slnPath -WaitSeconds 25

    # Dismiss dialogs
    Write-Host "Dismissing dialogs..."
    try {
        Dismiss-VSDialogsBestEffort -Retries 3 -InitialWaitSeconds 5 -BetweenRetriesSeconds 2
        Write-Host "Dialog dismissal complete."
    } catch {
        Write-Host "WARNING: Dialog dismissal failed: $($_.Exception.Message)"
    }

    $vsProc = Get-Process devenv -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($vsProc) {
        Write-Host "VS is running (PID: $($vsProc.Id))"
    } else {
        Write-Host "WARNING: VS process not found after launch."
    }

    Write-Host "=== create_class_file task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}

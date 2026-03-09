# Setup script for build_existing_solution task.
# Opens VS 2022 with the InventoryManager solution. Build output is cleaned first.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_build_existing_solution.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up build_existing_solution task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    Kill-AllVS2022

    # Ensure the InventoryManager project exists and is clean (no build output)
    $projDir = "C:\Users\Docker\source\repos\InventoryManager"
    if (-not (Test-Path "$projDir\InventoryManager.csproj")) {
        throw "InventoryManager project not found at: $projDir"
    }

    # Remove build output so the agent must build
    Remove-Item "$projDir\bin" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$projDir\obj" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Cleaned build output from InventoryManager."

    # Find the .sln file (dotnet new console doesn't create one, so create it)
    $slnPath = "$projDir\InventoryManager.sln"
    if (-not (Test-Path $slnPath)) {
        Write-Host "Creating solution file..."
        $dotnet = Find-DotnetExe
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        & $dotnet new sln -n InventoryManager -o $projDir --force 2>&1 | Out-Null
        & $dotnet sln "$projDir\InventoryManager.sln" add "$projDir\InventoryManager.csproj" 2>&1 | Out-Null
        $ErrorActionPreference = $prevEAP
        Write-Host "Solution file created: $slnPath"
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

    Write-Host "=== build_existing_solution task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}

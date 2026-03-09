# Setup script for fix_build_error task.
# Opens VS 2022 with the InventoryManager_broken solution (has 2 compile errors).

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_fix_build_error.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up fix_build_error task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    Kill-AllVS2022

    # Ensure the broken project exists
    $projDir = "C:\Users\Docker\source\repos\InventoryManager_broken"
    if (-not (Test-Path "$projDir\InventoryManager_broken.csproj")) {
        throw "InventoryManager_broken project not found at: $projDir"
    }

    # Clean build output
    Remove-Item "$projDir\bin" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$projDir\obj" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Cleaned build output from InventoryManager_broken."

    # Create .sln if not present
    $slnPath = "$projDir\InventoryManager_broken.sln"
    if (-not (Test-Path $slnPath)) {
        Write-Host "Creating solution file..."
        $dotnet = Find-DotnetExe
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        & $dotnet new sln -n InventoryManager_broken -o $projDir --force 2>&1 | Out-Null
        & $dotnet sln "$projDir\InventoryManager_broken.sln" add "$projDir\InventoryManager_broken.csproj" 2>&1 | Out-Null
        $ErrorActionPreference = $prevEAP
        Write-Host "Solution file created."
    }

    # Launch VS with the broken solution
    $devenvExe = Find-VS2022Exe
    Write-Host "VS executable: $devenvExe"
    Write-Host "Launching VS with InventoryManager_broken.sln..."
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

    Write-Host "=== fix_build_error task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}

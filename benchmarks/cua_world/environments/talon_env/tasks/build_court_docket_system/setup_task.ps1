Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_build_court_docket_system.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up build_court_docket_system task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # -----------------------------------------------------------------------
    # 1. Delete stale outputs from previous runs BEFORE recording timestamp
    # -----------------------------------------------------------------------

    # Remove any previously created docket_manager module
    $targetDir = "$Script:TalonUserDir\docket_manager"
    if (Test-Path $targetDir) {
        Remove-Item -Recurse -Force $targetDir
        Write-Host "Removed stale docket_manager directory"
    }

    # Remove any previously generated docket sheet output files
    $docDir = "C:\Users\Docker\Documents"
    New-Item -ItemType Directory -Force -Path $docDir | Out-Null
    Get-ChildItem -Path $docDir -Filter "docket_*.txt" -ErrorAction SilentlyContinue | Remove-Item -Force
    Write-Host "Cleaned stale docket output files from Documents"

    # -----------------------------------------------------------------------
    # 2. Record task start timestamp (AFTER cleanup)
    # -----------------------------------------------------------------------
    $timestamp = (Get-Date).ToString("o")
    [System.IO.File]::WriteAllText("C:\Users\Docker\task_start_ts_build_court_docket_system.txt", $timestamp)
    Write-Host "Task start time recorded: $timestamp"

    # -----------------------------------------------------------------------
    # 3. Ensure the court_docket.csv data file is available
    # -----------------------------------------------------------------------
    $csvSource = "C:\workspace\data\court_docket.csv"
    $csvDest   = "C:\Users\Docker\Desktop\TalonTasks\court_docket.csv"

    # Ensure TalonTasks directory exists
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop\TalonTasks" | Out-Null

    if (-not (Test-Path $csvSource)) {
        throw "Data file not found: $csvSource"
    }

    # Always copy fresh from source (reset to clean state)
    Copy-Item -Path $csvSource -Destination $csvDest -Force
    Write-Host "Copied court_docket.csv to TalonTasks ($((Get-Content $csvDest | Measure-Object -Line).Lines) lines)"

    # -----------------------------------------------------------------------
    # 4. Open File Explorer at the Talon user directory
    # -----------------------------------------------------------------------
    Open-FolderInteractive -FolderPath $Script:TalonUserDir -WaitSeconds 5

    # -----------------------------------------------------------------------
    # 5. Minimize terminal windows
    # -----------------------------------------------------------------------
    Minimize-TerminalWindows

    Write-Host "=== build_court_docket_system task setup complete ==="
    Write-Host "=== CSV: $csvDest (80 court cases) ==="
    Write-Host "=== Target: $targetDir (agent must create this) ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}

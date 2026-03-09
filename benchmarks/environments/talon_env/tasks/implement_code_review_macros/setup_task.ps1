Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_implement_code_review_macros.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up implement_code_review_macros task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # Record task start timestamp
    $timestamp = (Get-Date).ToString("o")
    [System.IO.File]::WriteAllText("C:\Users\Docker\task_start_ts_implement_code_review_macros.txt", $timestamp)

    # Create target directory (agent must create files from scratch)
    $targetDir = "$Script:CommunityDir\apps\github"
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

    # Remove pre-existing files to ensure clean start
    $talonFile = "$targetDir\github_review.talon"
    $pyFile    = "$targetDir\github_review.py"
    if (Test-Path $talonFile) { Remove-Item $talonFile -Force }
    if (Test-Path $pyFile)    { Remove-Item $pyFile    -Force }

    Write-Host "Target directory ready: $targetDir"

    # Open the community apps directory in File Explorer for orientation
    Start-Process explorer.exe -ArgumentList "$Script:CommunityDir\apps"
    Start-Sleep -Seconds 2

    # Open a reference file (an existing .talon file) as a syntax reference
    $sampleTalon = "$Script:CommunityDir\core\modes\sleep_mode.talon"
    if (-not (Test-Path $sampleTalon)) {
        # Fall back to any .talon file we can find
        $sampleTalon = (Get-ChildItem -Path $Script:CommunityDir -Filter "*.talon" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
    }
    if ($sampleTalon -and (Test-Path $sampleTalon)) {
        Open-FileInteractive -FilePath $sampleTalon -WaitSeconds 6
    }

    Minimize-TerminalWindows

    Write-Host "=== implement_code_review_macros task setup complete ==="
    Write-Host "=== Create github_review.talon and github_review.py in: $targetDir ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}

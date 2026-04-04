Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_build_vscode_voice_module.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up build_vscode_voice_module task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # Record task start timestamp
    $timestamp = (Get-Date).ToString("o")
    [System.IO.File]::WriteAllText("C:\Users\Docker\task_start_ts_build_vscode_voice_module.txt", $timestamp)

    # Create target directory (empty - agent must create files from scratch)
    $targetDir = "$Script:CommunityDir\apps\vscode"
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    Write-Host "Created target directory: $targetDir"

    # Ensure the apps directory itself exists (parent)
    $appsDir = "$Script:CommunityDir\apps"
    New-Item -ItemType Directory -Force -Path $appsDir | Out-Null

    # Remove any pre-existing vscode.talon or vscode.py to ensure a clean start
    $talonFile = "$targetDir\vscode.talon"
    $pyFile    = "$targetDir\vscode.py"
    if (Test-Path $talonFile) { Remove-Item $talonFile -Force }
    if (Test-Path $pyFile)    { Remove-Item $pyFile    -Force }

    # Open the community dir in File Explorer so agent can see the structure
    Start-Process explorer.exe -ArgumentList $Script:CommunityDir
    Start-Sleep -Seconds 2

    # Open Notepad++ with the target directory path so agent knows where to work
    $readmeFile = "$targetDir\README_TASK.txt"
    $readmeContent = @"
VS Code Voice Module Task
=========================
Create two files in this directory:
  1. vscode.talon  - context-scoped voice commands for VS Code
  2. vscode.py     - Python actions module for VS Code

This file can be deleted. It is here for orientation only.
"@
    [System.IO.File]::WriteAllText($readmeFile, $readmeContent)
    Open-FileInteractive -FilePath $readmeFile -WaitSeconds 6

    Minimize-TerminalWindows

    Write-Host "=== build_vscode_voice_module task setup complete ==="
    Write-Host "=== Agent must create vscode.talon and vscode.py in: $targetDir ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}

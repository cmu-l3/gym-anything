Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_create_voice_command.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up create_voice_command task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # Ensure TalonTasks directory exists
    $tasksDir = "C:\Users\Docker\Desktop\TalonTasks"
    New-Item -ItemType Directory -Force -Path $tasksDir | Out-Null

    # Create the starter .talon file with just a context header
    $talonFile = Join-Path $tasksDir "my_commands.talon"
    $starterContent = @"
# My custom Talon voice commands
-

"@
    [System.IO.File]::WriteAllText($talonFile, $starterContent)
    Write-Host "Created starter file: $talonFile"

    # Open the file in the text editor
    Write-Host "Opening my_commands.talon in editor..."
    Open-FileInteractive -FilePath $talonFile -WaitSeconds 8

    # Minimize terminal windows
    Minimize-TerminalWindows

    Write-Host "=== create_voice_command task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}

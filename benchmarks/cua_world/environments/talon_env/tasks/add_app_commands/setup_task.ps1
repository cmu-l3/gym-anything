Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_add_app_commands.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up add_app_commands task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # Ensure the community notepad.talon is present
    $notepadTalon = "$Script:CommunityDir\apps\notepad\notepad.talon"
    $notepadDir = "$Script:CommunityDir\apps\notepad"
    if (-not (Test-Path $notepadTalon)) {
        Write-Host "notepad.talon not found at community dir, copying from data..."
        $dataSource = "C:\workspace\data\community_sample\apps\notepad\notepad.talon"
        if (Test-Path $dataSource) {
            New-Item -ItemType Directory -Force -Path $notepadDir | Out-Null
            Copy-Item $dataSource -Destination $notepadTalon -Force
        } else {
            throw "notepad.talon not found in data either"
        }
    }

    # Reset the file to original state (in case of previous task runs)
    $dataSource = "C:\workspace\data\community_sample\apps\notepad\notepad.talon"
    if (Test-Path $dataSource) {
        Copy-Item $dataSource -Destination $notepadTalon -Force
        Write-Host "Reset notepad.talon to original state"
    }

    # Also ensure the notepad.py context matcher is present
    $notepadPy = "$Script:CommunityDir\apps\notepad\notepad.py"
    if (-not (Test-Path $notepadPy)) {
        $pySource = "C:\workspace\data\community_sample\apps\notepad\notepad.py"
        if (Test-Path $pySource) {
            Copy-Item $pySource -Destination $notepadPy -Force
        }
    }

    # Open the notepad.talon file in the editor
    Write-Host "Opening notepad.talon in editor..."
    Open-FileInteractive -FilePath $notepadTalon -WaitSeconds 8

    # Minimize terminal windows
    Minimize-TerminalWindows

    Write-Host "=== add_app_commands task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}

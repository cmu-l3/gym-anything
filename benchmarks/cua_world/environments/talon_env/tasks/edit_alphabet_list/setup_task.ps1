Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_edit_alphabet_list.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up edit_alphabet_list task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # Ensure the community letter.talon-list is present (from install step)
    $letterList = "$Script:CommunityDir\core\keys\letter.talon-list"
    if (-not (Test-Path $letterList)) {
        Write-Host "letter.talon-list not found at community dir, copying from data..."
        $dataSource = "C:\workspace\data\community_sample\core\keys\letter.talon-list"
        if (Test-Path $dataSource) {
            $destDir = "$Script:CommunityDir\core\keys"
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
            Copy-Item $dataSource -Destination $letterList -Force
        } else {
            throw "letter.talon-list not found in data either"
        }
    }

    # Reset the file to original state (in case of previous task runs)
    $dataSource = "C:\workspace\data\community_sample\core\keys\letter.talon-list"
    if (Test-Path $dataSource) {
        Copy-Item $dataSource -Destination $letterList -Force
        Write-Host "Reset letter.talon-list to original state"
    }

    # Open the letter list in the editor
    Write-Host "Opening letter.talon-list in editor..."
    Open-FileInteractive -FilePath $letterList -WaitSeconds 8

    # Minimize terminal windows
    Minimize-TerminalWindows

    Write-Host "=== edit_alphabet_list task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}

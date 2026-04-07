Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Setting up Multiecuscan environment ==="

# ── 1. Disable OneDrive and other distractions ─────────────────────────────
Write-Host "[1/5] Disabling OneDrive and system distractions..."
Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process -Name "OneDriveSetup" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
# Disable OneDrive auto-start via registry
try {
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Name "DisableFileSyncNGSC" -Value 1 -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue
} catch {
    Write-Host "  OneDrive registry cleanup: $($_.Exception.Message)"
}
# Disable OneDrive scheduled tasks
schtasks /Change /TN "\Microsoft\Windows\OneDrive\OneDrive Standalone Update Task" /Disable 2>&1 | Out-Null
schtasks /Change /TN "\OneDrive Reporting Task" /Disable 2>&1 | Out-Null
# Remove OneDrive from startup
$oneDrivePath = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
if (Test-Path $oneDrivePath) {
    Rename-Item $oneDrivePath "$oneDrivePath.disabled" -Force -ErrorAction SilentlyContinue
}
# Kill Edge update processes
Get-Process -Name "MicrosoftEdgeUpdate*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# ── 2. Set up Desktop directory structure ──────────────────────────────────
Write-Host "[2/5] Setting up Desktop directory..."
$desktop = "C:\Users\Docker\Desktop"
$dataDir = "$desktop\MultiecuscanData"
$tasksDir = "$desktop\MultiecuscanTasks"
New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
New-Item -ItemType Directory -Path $tasksDir -Force | Out-Null

# ── 3. Find Multiecuscan executable ────────────────────────────────────────
Write-Host "[3/5] Locating Multiecuscan executable..."
. C:\workspace\scripts\task_utils.ps1
$mesExe = Find-MultiecuscanExe
if ($mesExe) {
    Write-Host "Multiecuscan found at: $mesExe"
    # Store path for task scripts
    Set-Content -Path "$desktop\MultiecuscanTasks\.mes_exe_path" -Value $mesExe
} else {
    Write-Host "ERROR: Multiecuscan not found!"
    exit 1
}

# ── 3b. Ensure .NET ngen queue is drained ────────────────────────────────────
# If .NET 3.5 was installed recently (even from a cached image), ngen may still
# be processing queued items on this boot. MES will crash if ngen hasn't finished.
Write-Host "[3b/5] Ensuring .NET native images are compiled..."
$ngenPaths = @(
    "C:\Windows\Microsoft.NET\Framework\v2.0.50727\ngen.exe",
    "C:\Windows\Microsoft.NET\Framework64\v2.0.50727\ngen.exe"
)
foreach ($ngen in $ngenPaths) {
    if (Test-Path $ngen) {
        & $ngen executeQueuedItems 2>&1 | Out-Null
        Write-Host "  ngen queue drained: $ngen"
    }
}

# ── 4. Warm-up launch (triggers first-run dialogs, then kill) ──────────────
Write-Host "[4/5] Performing warm-up launch to clear first-run dialogs..."

$launched = Launch-MultiecuscanInteractive -MesExe $mesExe -WaitSeconds 25
if ($launched) {
    Write-Host "Warm-up process running, killing..."
    Stop-Multiecuscan
} else {
    Write-Host "WARNING: Warm-up launch may not have started Multiecuscan"
}
Start-Sleep -Seconds 3

Write-Host "Warm-up launch completed"

# ── 5. Minimize terminal windows ──────────────────────────────────────────
Write-Host "[5/5] Minimizing terminal windows..."

# Use SW_HIDE (0) instead of SW_MINIMIZE (6) to fully hide terminal windows
$minimizeCode = @'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Min {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
Get-Process | Where-Object {
    ($_.ProcessName -match "cmd|powershell|WindowsTerminal|conhost") -and $_.MainWindowHandle -ne [IntPtr]::Zero
} | ForEach-Object {
    [Win32Min]::ShowWindow($_.MainWindowHandle, 0) | Out-Null
}
'@

try {
    $minScript = "$tempDir\minimize_terminals.ps1"
    Set-Content -Path $minScript -Value $minimizeCode
    # Use hidden window to avoid creating ANOTHER visible terminal
    $trCmd = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -File `"$minScript`""
    schtasks /Create /SC ONCE /IT /TR "$trCmd" /TN "MinTerminals" /SD 01/01/2099 /ST 00:00 /RL HIGHEST /F 2>&1 | Out-Null
    schtasks /Run /TN "MinTerminals" 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    schtasks /Delete /TN "MinTerminals" /F 2>&1 | Out-Null
    Remove-Item $minScript -Force -ErrorAction SilentlyContinue
} catch {
    Write-Host "  Terminal minimize: $($_.Exception.Message)"
}

Write-Host "=== Multiecuscan environment setup complete ==="

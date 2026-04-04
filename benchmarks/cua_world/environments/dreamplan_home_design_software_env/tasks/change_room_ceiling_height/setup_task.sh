#!/bin/bash
echo "=== Setting up change_room_ceiling_height task ==="

# 1. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Launch DreamPlan via PowerShell
# We use PowerShell to handle Windows GUI operations
# This script ensures the app is open and tries to load a sample if possible
cat << 'PS_EOF' > /tmp/setup_dreamplan.ps1
$ErrorActionPreference = "Stop"

# Define paths
$exePath = "C:\Program Files (x86)\NCH Software\DreamPlan\dreamplan.exe"
$samplePath = "C:\ProgramData\NCH Software\DreamPlan\Samples\Sample House.dpp"
# Fallback sample path if ProgramData structure differs
$samplePath2 = "C:\Users\Public\Documents\NCH Software\DreamPlan\Samples\Sample House.dpp"

# Check if DreamPlan is running
$proc = Get-Process -Name "dreamplan" -ErrorAction SilentlyContinue

if (-not $proc) {
    Write-Host "Starting DreamPlan..."
    if (Test-Path $samplePath) {
        Start-Process $exePath -ArgumentList "`"$samplePath`""
    } elseif (Test-Path $samplePath2) {
        Start-Process $exePath -ArgumentList "`"$samplePath2`""
    } else {
        # Start without arguments if sample not found, expect agent to handle or default load
        Start-Process $exePath
    }
    Start-Sleep -Seconds 10
} else {
    Write-Host "DreamPlan is already running."
}

# Maximize Window using user32.dll
Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);' -Name "Win32ShowWindow" -Namespace Win32Functions
$proc = Get-Process -Name "dreamplan" -ErrorAction SilentlyContinue
if ($proc) {
    $hwnd = $proc.MainWindowHandle
    if ($hwnd -ne [IntPtr]::Zero) {
        [Win32Functions.Win32ShowWindow]::ShowWindow($hwnd, 3) # 3 = SW_MAXIMIZE
    }
}

# Ensure window is focused
$wsh = New-Object -ComObject WScript.Shell
$wsh.AppActivate("DreamPlan")
PS_EOF

# Execute the PowerShell script
powershell -ExecutionPolicy Bypass -File /tmp/setup_dreamplan.ps1

# 3. Take initial screenshot for evidence
# Using a PowerShell one-liner for screenshot on Windows
powershell -Command "
Add-Type -AssemblyName System.Windows.Forms;
Add-Type -AssemblyName System.Drawing;
$screen = [System.Windows.Forms.Screen]::PrimaryScreen;
$bitmap = New-Object System.Drawing.Bitmap $screen.Bounds.Width, $screen.Bounds.Height;
$graphics = [System.Drawing.Graphics]::FromImage($bitmap);
$graphics.CopyFromScreen($screen.Bounds.Location, [System.Drawing.Point]::Empty, $screen.Bounds.Size);
$bitmap.Save('C:\tmp\task_initial.png');
$graphics.Dispose();
$bitmap.Dispose();
"

echo "=== Task setup complete ==="
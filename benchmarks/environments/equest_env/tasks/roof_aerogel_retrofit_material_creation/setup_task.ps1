# Note: This is a PowerShell script wrapped in the .sh file extension for the framework compatibility 
# if needed, but based on the hooks in task.json, it will be executed as PowerShell.
# We will provide the content as a PowerShell script.

<#
.SYNOPSIS
    Setup script for roof_aerogel_retrofit_material_creation
#>

$ErrorActionPreference = "Stop"

Write-Host "=== Setting up Task: Roof Aerogel Retrofit ==="

# 1. Record Task Start Time
$startTime = [DateTimeOffset]::Now.ToUnixTimeSeconds()
$startTime | Out-File -FilePath "C:\Users\Docker\task_start_time.txt" -Encoding ascii -Force

# 2. Ensure eQUEST is running and Project is Loaded
$projectPath = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding\4StoreyBuilding.inp"
$equestProcess = Get-Process -Name "eQUEST" -ErrorAction SilentlyContinue

if (-not $equestProcess) {
    Write-Host "Starting eQUEST..."
    # Start eQUEST directly opening the project file
    Start-Process -FilePath "C:\Program Files (x86)\eQUEST 3-65\eQUEST.exe" -ArgumentList "`"$projectPath`"" -PassThru
    
    # Wait for window
    $timeout = 60
    $timer = 0
    while ($timer -lt $timeout) {
        if (Get-Process -Name "eQUEST" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like "*4StoreyBuilding*" }) {
            Write-Host "eQUEST window detected."
            break
        }
        Start-Sleep -Seconds 1
        $timer++
    }
} else {
    Write-Host "eQUEST is already running."
    # Ensure it's the right project (basic check)
    if (-not ($equestProcess.MainWindowTitle -like "*4StoreyBuilding*")) {
        Write-Host "WARNING: eQUEST running but window title doesn't match project. Restarting..."
        Stop-Process -Name "eQUEST" -Force
        Start-Sleep -Seconds 2
        Start-Process -FilePath "C:\Program Files (x86)\eQUEST 3-65\eQUEST.exe" -ArgumentList "`"$projectPath`""
        Start-Sleep -Seconds 15
    }
}

# 3. Focus and Maximize Window (using external tool if available or powershell native)
# Using a simple powershell window management approach
Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class Win32 {
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetForegroundWindow(IntPtr hWnd);
    }
"@

$proc = Get-Process -Name "eQUEST" -ErrorAction SilentlyContinue
if ($proc) {
    [Win32]::ShowWindow($proc.MainWindowHandle, 3) # 3 = SW_MAXIMIZE
    [Win32]::SetForegroundWindow($proc.MainWindowHandle)
}

# 4. Cleanup any previous result artifacts
if (Test-Path "C:\Users\Docker\task_result.json") { Remove-Item "C:\Users\Docker\task_result.json" -Force }

Write-Host "=== Setup Complete ==="
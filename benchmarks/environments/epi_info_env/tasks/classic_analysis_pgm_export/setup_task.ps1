# Note: This is actually a PowerShell script (setup_task.ps1) wrapped in sh for the framework
# The framework executes the command specified in hooks.pre_task

# Content for C:\workspace\tasks\classic_analysis_pgm_export\setup_task.ps1
$ErrorActionPreference = "Stop"

Write-Output "=== Setting up Classic Analysis Task ==="

# 1. Record task start time (Unix timestamp)
$startTime = [int][double]::Parse((Get-Date -UFormat %s))
$startTime | Out-File "C:\temp\task_start_time.txt" -Encoding ASCII

# 2. Clean up previous artifacts
$exportPath = "C:\Users\Docker\Documents\OswegoIllExport.csv"
if (Test-Path $exportPath) {
    Remove-Item $exportPath -Force
    Write-Output "Removed existing export file."
}

# 3. Ensure Epi Info 7 is running
$processName = "Epi Info 7"
if (-not (Get-Process $processName -ErrorAction SilentlyContinue)) {
    Write-Output "Starting Epi Info 7..."
    # Try common installation paths
    $paths = @(
        "C:\Epi Info 7\Epi Info 7.exe",
        "C:\Program Files (x86)\Epi Info 7\Epi Info 7.exe",
        "C:\Program Files\Epi Info 7\Epi Info 7.exe"
    )
    
    foreach ($path in $paths) {
        if (Test-Path $path) {
            Start-Process $path
            break
        }
    }
    Start-Sleep -Seconds 10
}

# 4. Maximize the window using a C# snippet for SendMessage
Add-Type @"
  using System;
  using System.Runtime.InteropServices;
  public class Win32 {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  }
"@

$proc = Get-Process $processName -ErrorAction SilentlyContinue | Select-Object -First 1
if ($proc) {
    [Win32]::ShowWindow($proc.MainWindowHandle, 3) # 3 = SW_MAXIMIZE
    [Win32]::SetForegroundWindow($proc.MainWindowHandle)
}

# 5. Capture Initial Screenshot
# (Assuming a screenshot tool exists or using a framework hook, but providing a script-based fallback if available)
# Using python if installed, otherwise relying on framework
if (Get-Command python -ErrorAction SilentlyContinue) {
    python -c "import pyautogui; pyautogui.screenshot('C:\\temp\\task_initial.png')" 2>$null
}

Write-Output "=== Setup Complete ==="
# Note: This is actually a PowerShell script (setup_task.ps1) as required by the Windows environment
# but named with .sh extension here for syntax highlighting if the system requires it.
# The task.json refers to it as setup_task.ps1

$ErrorActionPreference = "SilentlyContinue"

Write-Host "=== Setting up Configure Chemical Safety Data Task ==="

# 1. Timestamp for anti-gaming
$startTime = [int64]((Get-Date).ToUniversalTime() - (Get-Date "1/1/1970")).TotalSeconds
$startTime | Out-File -FilePath "C:\workspace\task_start_time.txt" -Encoding ASCII

# 2. Define CAMEO paths
$cameoPath = "C:\Program Files (x86)\CAMEO Data Manager\CAMEOfm.exe"
# Fallback path
if (-not (Test-Path $cameoPath)) {
    $cameoPath = "C:\CAMEOfm\CAMEOfm.exe"
}

# 3. Ensure CAMEO is running
$process = Get-Process "CAMEOfm" -ErrorAction SilentlyContinue
if (-not $process) {
    Write-Host "Starting CAMEO Data Manager..."
    Start-Process -FilePath $cameoPath
    Start-Sleep -Seconds 10
} else {
    Write-Host "CAMEO is already running."
}

# 4. Maximize the window (using embedded C# for Win32 API access)
Add-Type @"
  using System;
  using System.Runtime.InteropServices;
  public class Win32 {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
  }
"@

$process = Get-Process "CAMEOfm" -ErrorAction SilentlyContinue
if ($process) {
    $hwnd = $process.MainWindowHandle
    if ($hwnd -ne [IntPtr]::Zero) {
        # SW_MAXIMIZE = 3
        [Win32]::ShowWindow($hwnd, 3)
        [Win32]::SetForegroundWindow($hwnd)
    }
}

Start-Sleep -Seconds 2

# 5. Capture initial screenshot
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$screen = [System.Windows.Forms.Screen]::PrimaryScreen
$bitmap = New-Object System.Drawing.Bitmap $screen.Bounds.Width, $screen.Bounds.Height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($screen.Bounds.X, $screen.Bounds.Y, 0, 0, $bitmap.Size)
$bitmap.Save("C:\workspace\task_initial.png", [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()

Write-Host "=== Setup Complete ==="
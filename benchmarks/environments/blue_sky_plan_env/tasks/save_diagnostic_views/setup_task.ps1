# NOTE: This is actually a PowerShell script (setup_task.ps1) for the Windows environment
# but we use the .sh extension logic in the prompt's context to indicate it's the setup script.
# In the real environment, this should be saved as setup_task.ps1

<#
.SYNOPSIS
    Setup script for save_diagnostic_views task
#>

$ErrorActionPreference = "Stop"
Write-Host "=== Setting up save_diagnostic_views task ==="

# 1. Create timestamp for anti-gaming
$startTime = [DateTimeOffset]::Now.ToUnixTimeSeconds()
$startTime | Out-File "C:\tmp\task_start_time.txt" -Encoding ascii

# 2. Setup output directory (clean state)
$outputDir = "C:\Users\Docker\Documents\CasePresentation"
if (Test-Path $outputDir) {
    Write-Host "Cleaning existing output directory..."
    Remove-Item $outputDir -Recurse -Force
}
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

# 3. Ensure Blue Sky Plan is running
$proc = Get-Process "BlueSkyPlan" -ErrorAction SilentlyContinue
if (-not $proc) {
    Write-Host "Starting Blue Sky Plan..."
    # Attempt standard install paths
    $possiblePaths = @(
        "C:\Program Files\Blue Sky Bio\Blue Sky Plan 4\BlueSkyPlan.exe",
        "C:\Program Files\Blue Sky Bio\Blue Sky Plan\BlueSkyPlan.exe",
        "C:\Program Files\BlueSkyPlan\BlueSkyPlan.exe"
    )
    
    $started = $false
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            Start-Process $path
            $started = $true
            break
        }
    }
    
    if (-not $started) {
        # Fallback to shell execution if path unknown
        try {
            Start-Process "BlueSkyPlan"
            $started = $true
        } catch {
            Write-Warning "Could not start Blue Sky Plan automatically. Agent will need to launch it."
        }
    }
    
    if ($started) {
        # Wait for window
        Start-Sleep -Seconds 10
    }
}

# 4. Maximize Window (via simple PowerShell automation if possible, else rely on Agent)
# Windows containers often lack full WM control, but we try standard hook
try {
    Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);' -Name "Win32ShowWindow" -Namespace Win32
    $proc = Get-Process "BlueSkyPlan" -ErrorAction SilentlyContinue
    if ($proc) {
        [Win32.Win32ShowWindow]::ShowWindow($proc.MainWindowHandle, 3) # 3 = SW_MAXIMIZE
    }
} catch {
    Write-Host "Could not maximize window via script (harmless)"
}

# 5. Take initial screenshot
# Using .NET classes available in PowerShell
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    
    $graphics.CopyFromScreen($screen.Left, $screen.Top, 0, 0, $bitmap.Size)
    $bitmap.Save("C:\tmp\task_initial.png", [System.Drawing.Imaging.ImageFormat]::Png)
    
    $graphics.Dispose()
    $bitmap.Dispose()
    Write-Host "Initial screenshot captured."
} catch {
    Write-Warning "Failed to capture initial screenshot: $_"
}

Write-Host "=== Setup Complete ==="
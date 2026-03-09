#!/bin/powershell
# Setup script for Organize Inventory Categories task
# Note: This is a PowerShell script (setup_task.ps1) executed by the Windows environment

Write-Host "=== Setting up Organize Inventory Categories Task ==="

# 1. timestamp for anti-gaming
$startTime = [int][double]::Parse((Get-Date -UFormat %s))
$startTime | Out-File -FilePath "C:\Users\Docker\Documents\task_start_time.txt" -Encoding ascii

# 2. Create the Inventory CSV file
$csvContent = @"
ItemName,SKU,Price
Coffee Beans 1lb,BEV-001,12.99
Green Tea Box,BEV-002,6.49
Orange Juice 64oz,BEV-003,4.99
Trail Mix Bag,SNK-001,7.99
Granola Bars 6pk,SNK-002,5.49
Potato Chips Family Size,SNK-003,4.29
USB-C Cable 6ft,ELC-001,9.99
Wireless Mouse,ELC-002,24.99
Phone Charger 20W,ELC-003,14.99
Notebook College Ruled,STN-001,3.49
Ballpoint Pen 10pk,STN-002,5.99
Sticky Notes 3x3,STN-003,2.99
"@

$csvPath = "C:\Users\Docker\Documents\inventory_items.csv"
$csvContent | Out-File -FilePath $csvPath -Encoding UTF8
Write-Host "Created inventory CSV at $csvPath"

# 3. Clean up previous run artifacts
if (Test-Path "C:\Users\Docker\Documents\category_assignments.txt") {
    Remove-Item "C:\Users\Docker\Documents\category_assignments.txt" -Force
}

# 4. Start Copper POS
Write-Host "Starting Copper Point of Sale..."
$copperProcess = Get-Process -Name "copper" -ErrorAction SilentlyContinue
if (-not $copperProcess) {
    Start-Process "C:\Program Files (x86)\NCH Software\Copper\copper.exe"
    Start-Sleep -Seconds 5
}

# 5. Ensure Window is Open and Maximized
# Using a small inline C# snippet for Window management if strictly needed, 
# but usually relying on the agent to handle window focus is safer in simple setups.
# However, providing a maximized window is best practice.

Add-Type -MemberDefinition @"
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
"@ -Name "Win32ShowWindowAsync" -Namespace Win32Functions

$proc = Get-Process -Name "copper" -ErrorAction SilentlyContinue
if ($proc) {
    $hwnd = $proc.MainWindowHandle
    if ($hwnd -ne [IntPtr]::Zero) {
        # SW_SHOWMAXIMIZED = 3
        [Win32Functions.Win32ShowWindowAsync]::ShowWindow($hwnd, 3)
        [Win32Functions.Win32ShowWindowAsync]::SetForegroundWindow($hwnd)
    }
}

# 6. Capture Initial Screenshot (using built-in Windows capability if available, or just skip)
# The framework usually handles step recording.

Write-Host "=== Setup Complete ==="
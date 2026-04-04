#!/bin/bash
echo "=== Setting up Customize Fibonacci Levels task ==="

# 1. Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Execute Windows/PowerShell setup logic
# We use PowerShell to ensure NT8 is running and focused
powershell.exe -Command "& {
    Write-Host 'Checking NinjaTrader process...'
    if (-not (Get-Process NinjaTrader -ErrorAction SilentlyContinue)) {
        Write-Host 'Starting NinjaTrader...'
        Start-Process 'C:\Program Files\NinjaTrader 8\bin\NinjaTrader.exe'
        Start-Sleep -Seconds 15
    }

    # Attempt to maximize window (basic approach via Shell object)
    $wsh = New-Object -ComObject WScript.Shell
    if ($wsh.AppActivate('NinjaTrader')) {
        Start-Sleep -Milliseconds 500
        # Send Alt+Space, x to maximize (keyboard shortcut method)
        $wsh.SendKeys('% n') 
        Start-Sleep -Milliseconds 500
        $wsh.SendKeys('% x')
    }
}"

# 3. Take initial screenshot (using a Windows-compatible screenshot tool or PowerShell)
# In this environment, we can try using the host's scrot via display or powershell
# Using PowerShell to capture screen if scrot fails
if ! which scrot > /dev/null; then
    powershell.exe -Command "& {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($screen.Left, $screen.Top, 0, 0, $bitmap.Size)
        $bitmap.Save('C:\tmp\task_initial.png')
    }"
    # Move to standard linux path if needed/possible, or just leave for verification
    cp /mnt/c/tmp/task_initial.png /tmp/task_initial.png 2>/dev/null || true
else
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
fi

echo "=== Setup complete ==="
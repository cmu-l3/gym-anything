#!/bin/bash
echo "=== Setting up Configure Regional Settings Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create a PowerShell setup script to handle Windows interactions
cat > /tmp/setup_copper.ps1 << 'PS_EOF'
$ErrorActionPreference = "Stop"

# 1. Reset Registry to US Defaults (Deterministic Start)
Write-Host "Resetting configuration to defaults..."
$regPath = "HKCU:\Software\NCH Software\Copper"
if (Test-Path $regPath) {
    # We attempt to reset key values if they exist, or just rely on UI interaction
    # For safety in this task, we won't delete the whole key to avoid breaking license info
    # preventing the app from starting, but we will try to set specific values if they exist.
    try {
        Set-ItemProperty -Path "$regPath\Settings" -Name "CurrencySymbol" -Value "$" -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "$regPath\Settings" -Name "DateFormat" -Value "MM/dd/yyyy" -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "$regPath\Tax" -Name "TaxName1" -Value "Sales Tax" -ErrorAction SilentlyContinue
    } catch {
        Write-Host "Note: Registry keys not ready for reset, skipping."
    }
}

# 2. Start Copper POS
Write-Host "Starting Copper Point of Sale..."
$process = Get-Process -Name "copper" -ErrorAction SilentlyContinue
if (-not $process) {
    Start-Process "C:\Program Files (x86)\NCH Software\Copper\copper.exe"
    Start-Sleep -Seconds 5
}

# 3. Maximize Window
Write-Host "Maximizing Window..."
# Simple maximize via shortcut trick or assuming user will interact
# We'll use a retry loop to find the window
for ($i=0; $i -lt 10; $i++) {
    $wshell = New-Object -ComObject WScript.Shell
    if ($wshell.AppActivate("Copper Point of Sale")) {
        Start-Sleep -Milliseconds 500
        $wshell.SendKeys("% x") # Alt+Space, x to Maximize
        break
    }
    Start-Sleep -Seconds 1
}

Write-Host "Setup complete."
PS_EOF

# Execute the PowerShell script
powershell.exe -ExecutionPolicy Bypass -File /tmp/setup_copper.ps1

# Take initial screenshot using nircmd or similar if available, or fallback to scrot if X11 is bridged
# Since this is likely a Windows container, we use a powershell method for screenshot if strictly Windows,
# but the env specification suggests X11/VNC access might be available via host.
# We will assume standard X11 tools are available in the shell environment (Git Bash/Cygwin/WSL)
# or use a PowerShell screenshot tool.

echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

# If scrot failed (pure Windows env), try PowerShell screenshot
if [ ! -f /tmp/task_initial.png ]; then
    powershell.exe -Command "
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    $bitmap = New-Object System.Drawing.Bitmap $screen.Bounds.Width, $screen.Bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($screen.Bounds.X, $screen.Bounds.Y, 0, 0, $bitmap.Size)
    $bitmap.Save('C:\tmp\task_initial.png')" 2>/dev/null || true
    
    # Move from C:\tmp to /tmp if needed (path mapping)
    if [ -f "/c/tmp/task_initial.png" ]; then
        mv /c/tmp/task_initial.png /tmp/task_initial.png
    fi
fi

echo "=== Task setup complete ==="
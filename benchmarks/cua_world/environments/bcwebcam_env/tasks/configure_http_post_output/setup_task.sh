#!/bin/bash
echo "=== Setting up HTTP POST configuration task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure working temp directory exists cross-platform (Git Bash / WSL compatible)
powershell.exe -Command "
\$tempDir = 'C:\tmp'
if (-not (Test-Path \$tempDir)) { New-Item -ItemType Directory -Force -Path \$tempDir | Out-Null }
"

# Start bcWebCam if it's not already running
powershell.exe -Command "
\$proc = Get-Process -Name 'bcWebCam' -ErrorAction SilentlyContinue
if (-not \$proc) {
    Write-Output 'Starting bcWebCam...'
    Start-Process 'C:\Program Files (x86)\bcWebCam\bcWebCam.exe' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
} else {
    Write-Output 'bcWebCam is already running.'
}
"

# Dismiss any potential blocking startup dialogs (Send Escape twice)
powershell.exe -Command "
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Milliseconds 500
[System.Windows.Forms.SendKeys]::SendWait('{ESC}')
"

# Take initial screenshot natively using Windows libraries to ensure reliable GUI capture
powershell.exe -Command "
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$bmp = New-Object System.Drawing.Bitmap([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width, [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)
\$gfx = [System.Drawing.Graphics]::FromImage(\$bmp)
\$gfx.CopyFromScreen(0, 0, 0, 0, \$bmp.Size)
\$bmp.Save('C:\tmp\task_initial.png', [System.Drawing.Imaging.ImageFormat]::Png)
\$gfx.Dispose()
\$bmp.Dispose()
"

# Also try framework tools as fallback
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
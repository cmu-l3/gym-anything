#!/bin/bash
echo "=== Setting up create_line_forecast task ==="

# Record task start time for anti-gaming (using Windows PowerShell to ensure sync)
powershell.exe -Command "Get-Date -UFormat '%s' | Out-File -FilePath C:\tmp\task_start_time.txt -Encoding ascii"

# Ensure Oracle Analytics Desktop is running
# Using PowerShell to check process and start if needed
powershell.exe -Command "
    \$proc = Get-Process -Name 'DVDesktop' -ErrorAction SilentlyContinue
    if (-not \$proc) {
        Write-Host 'Starting Oracle Analytics Desktop...'
        Start-Process 'C:\Program Files\Oracle Analytics Desktop\DVDesktop.exe'
        Start-Sleep -Seconds 30
    }
"

# Wait for window and maximize
powershell.exe -Command "
    Add-Type -MemberDefinition '[DllImport(\"user32.dll\")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow); [DllImport(\"user32.dll\")] public static extern bool SetForegroundWindow(IntPtr hWnd);' -Name 'Win32' -Namespace Win32Functions
    
    for (\$i = 0; \$i -lt 30; \$i++) {
        \$proc = Get-Process -Name 'DVDesktop' -ErrorAction SilentlyContinue | Where-Object { \$_.MainWindowTitle -ne '' } | Select-Object -First 1
        if (\$proc) {
            Write-Host 'Maximizing OAD window...'
            [Win32Functions.Win32]::ShowWindow(\$proc.MainWindowHandle, 3) # SW_MAXIMIZE
            [Win32Functions.Win32]::SetForegroundWindow(\$proc.MainWindowHandle)
            break
        }
        Start-Sleep -Seconds 2
    }
"

# Dismiss any startup dialogs (Esc key injection)
powershell.exe -Command "
    Add-Type -AssemblyName System.Windows.Forms
    Start-Sleep -Seconds 2
    [System.Windows.Forms.SendKeys]::SendWait('{ESC}')
"

# Take initial screenshot
powershell.exe -Command "
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    \$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    \$bitmap = New-Object System.Drawing.Bitmap(\$screen.Width, \$screen.Height)
    \$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
    \$graphics.CopyFromScreen(\$screen.Location, [System.Drawing.Point]::Empty, \$screen.Size)
    \$bitmap.Save('C:\tmp\task_initial.png')
    \$graphics.Dispose()
    \$bitmap.Dispose()
"

echo "=== Task setup complete ==="
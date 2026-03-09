#!/bin/bash
set -e
echo "=== Setting up create_investigation_form task ==="

# Define paths (Git Bash / Cygwin style for Windows paths)
PROJECT_DIR="/c/Users/Docker/Documents/Epi Info 7/Projects/NorovirusOutbreak"

# 1. Anti-gaming: Record start time
date +%s > /tmp/task_start_time.txt

# 2. Clean State: Remove project directory if it exists
if [ -d "$PROJECT_DIR" ]; then
    echo "Removing stale project directory..."
    rm -rf "$PROJECT_DIR"
fi

# Ensure parent directory exists
mkdir -p "/c/Users/Docker/Documents/Epi Info 7/Projects"

# 3. Start Application (Epi Info 7)
# Using powershell to launch windows exe properly
echo "Launching Epi Info 7..."
powershell.exe -Command "Start-Process 'C:\\Epi Info 7\\EpiInfo.exe'"

# 4. Wait for window and maximize
echo "Waiting for Epi Info 7..."
for i in {1..30}; do
    # Check for process
    if powershell.exe -Command "Get-Process EpiInfo -ErrorAction SilentlyContinue" | grep -q "EpiInfo"; then
        echo "Process found."
        break
    fi
    sleep 1
done

sleep 5

# Maximize window using PowerShell (no wmctrl on standard Windows usually, but this works via PS)
powershell.exe -Command "
\$code = '[DllImport(\"user32.dll\")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);'
\$type = Add-Type -MemberDefinition \$code -Name Win32ShowWindow -Namespace Win32 -PassThru
\$proc = Get-Process -Name EpiInfo -ErrorAction SilentlyContinue
if (\$proc) { \$type::ShowWindow(\$proc.MainWindowHandle, 3) } # 3 = SW_MAXIMIZE
"

# 5. Capture initial screenshot
# Using screenshot tool if available, or PowerShell fallback
echo "Capturing initial screenshot..."
powershell.exe -Command "
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$screen = [System.Windows.Forms.Screen]::PrimaryScreen
\$bitmap = New-Object System.Drawing.Bitmap \$screen.Bounds.Width, \$screen.Bounds.Height
\$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
\$graphics.CopyFromScreen(\$screen.Bounds.X, \$screen.Bounds.Y, 0, 0, \$bitmap.Size)
\$bitmap.Save('C:\\workspace\\task_initial.png')
"

echo "=== Task setup complete ==="
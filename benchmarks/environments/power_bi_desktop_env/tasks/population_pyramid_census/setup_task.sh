#!/bin/bash
set -e
echo "=== Setting up Population Pyramid task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure the data directory exists
mkdir -p "/c/Users/Docker/Desktop/PowerBITasks" 2>/dev/null || mkdir -p "/home/ga/Desktop/PowerBITasks" 2>/dev/null || true
DATA_DIR="/c/Users/Docker/Desktop/PowerBITasks"

# If we are in a linux environment mapping to windows, path might differ. 
# Attempting to use the path consistent with the description.
# In this environment, we often write to the shared mount or use powershell to write the file.

# Generate the CSV file using PowerShell to ensure Windows path compatibility/line endings
# Or write locally if the mount is shared. Assuming standard Gym setup where we can write to filesystem.

cat <<EOF > /tmp/create_data.ps1
\$path = "C:\\Users\\Docker\\Desktop\\PowerBITasks"
if (!(Test-Path \$path)) { New-Item -ItemType Directory -Force -Path \$path }
\$csvContent = @"
Age_Group,Sort_Order,Gender,Population
0-4,1,Male,10200
0-4,1,Female,9800
5-9,2,Male,10500
5-9,2,Female,10100
10-14,3,Male,10800
10-14,3,Female,10400
15-19,4,Male,11000
15-19,4,Female,10600
20-24,5,Male,11200
20-24,5,Female,11000
25-29,6,Male,12000
25-29,6,Female,11800
30-34,7,Male,11500
30-34,7,Female,11600
35-39,8,Male,11000
35-39,8,Female,11200
40-44,9,Male,10500
40-44,9,Female,10800
45-49,10,Male,10000
45-49,10,Female,10200
50-54,11,Male,9500
50-54,11,Female,9800
55-59,12,Male,9000
55-59,12,Female,9400
60-64,13,Male,8000
60-64,13,Female,8500
65-69,14,Male,7000
65-69,14,Female,7600
70-74,15,Male,5500
70-74,15,Female,6200
75-79,16,Male,4000
75-79,16,Female,4800
80-84,17,Male,2500
80-84,17,Female,3200
85+,18,Male,1500
85+,18,Female,2200
"@
Set-Content -Path "\$path\\census_2020.csv" -Value \$csvContent
Write-Host "Data created at \$path\\census_2020.csv"
EOF

# Execute the PowerShell script
powershell -ExecutionPolicy Bypass -File /tmp/create_data.ps1

# Ensure Power BI is running
echo "Checking Power BI status..."
if ! tasklist.exe | grep -i "PBIDesktop" > /dev/null; then
    echo "Starting Power BI Desktop..."
    # Launch via PowerShell to handle path correctly
    powershell -Command "Start-Process 'PBIDesktop'"
    
    # Wait for window
    for i in {1..60}; do
        if tasklist.exe | grep -i "PBIDesktop" > /dev/null; then
            echo "Power BI process detected"
            break
        fi
        sleep 1
    done
    sleep 10 # Wait for UI
fi

# Attempt to maximize window using a PowerShell snippet (more reliable on Windows than wmctrl)
cat <<EOF > /tmp/maximize_pbi.ps1
\$code = @"
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern int SetForegroundWindow(IntPtr hwnd);
"@
\$type = Add-Type -MemberDefinition \$code -Name Win32ShowWindowAsync -Namespace Win32Functions -PassThru
\$pbi = Get-Process -Name PBIDesktop -ErrorAction SilentlyContinue
if (\$pbi) {
    \$hwnd = \$pbi.MainWindowHandle
    if (\$hwnd -ne [IntPtr]::Zero) {
        \$type::ShowWindowAsync(\$hwnd, 3) # 3 = SW_MAXIMIZE
        \$type::SetForegroundWindow(\$hwnd)
    }
}
EOF
powershell -ExecutionPolicy Bypass -File /tmp/maximize_pbi.ps1

# Take initial screenshot using python or similar tool available in env
# Assuming standard gym utilities are available or using powershell screenshot
cat <<EOF > /tmp/screenshot.ps1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$screen = [System.Windows.Forms.Screen]::PrimaryScreen
\$bitmap = New-Object System.Drawing.Bitmap \$screen.Bounds.Width, \$screen.Bounds.Height
\$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
\$graphics.CopyFromScreen(\$screen.Bounds.X, \$screen.Bounds.Y, 0, 0, \$bitmap.Size)
\$bitmap.Save("C:\\tmp\\task_initial.png")
EOF
mkdir -p "C:\tmp" 2>/dev/null || true
powershell -ExecutionPolicy Bypass -File /tmp/screenshot.ps1

echo "=== Task setup complete ==="
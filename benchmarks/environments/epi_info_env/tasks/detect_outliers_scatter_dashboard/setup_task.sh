#!/bin/bash
echo "=== Setting up detect_outliers_scatter_dashboard task ==="

# Define paths
# Note: Using Windows paths for PowerShell commands
DATA_DIR_WIN="C:\\Users\\Docker\\Documents\\DiabetesData"
CSV_PATH_WIN="$DATA_DIR_WIN\\diabetes_surveillance.csv"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create data directory using PowerShell
powershell.exe -Command "New-Item -Path '$DATA_DIR_WIN' -ItemType Directory -Force | Out-Null"

echo "Generating dataset with injected outlier..."
# Generate CSV with Python (embedded in the script)
# We use python to ensure realistic distribution + one specific outlier
python3 -c "
import csv
import random
import os

# Ensure we write to the correct location relative to where the script runs or absolute path
# We'll write to a temp file then move it via powershell if needed, 
# or directly if we can access the mount. 
# Assuming standard environment where we can write to local disk.

headers = ['PatientID', 'Pregnancies', 'Glucose', 'BloodPressure', 'SkinThickness', 'Insulin', 'BMI', 'DiabetesPedigreeFunction', 'Age', 'Outcome']
records = []

# Generate 500 records
for i in range(1, 501):
    pid = i
    preg = random.randint(0, 10)
    gluc = int(random.gauss(120, 30))
    bp = int(random.gauss(70, 10))
    skin = int(random.gauss(20, 10))
    insulin = int(random.gauss(80, 20))
    bmi = round(random.gauss(32, 6), 1)
    pedi = round(random.uniform(0.1, 2.5), 3)
    age = int(random.gauss(33, 10))
    outcome = 1 if gluc > 140 else 0
    
    # Ensure bounds
    gluc = max(50, min(200, gluc))
    bmi = max(15.0, min(60.0, bmi))
    age = max(21, min(80, age))
    
    # INJECT OUTLIER at ID 450
    if pid == 450:
        bmi = 175.6  # Decimal error (should be 17.5 or 75.6)
        gluc = 125   # Normal glucose to make it stand out only on Y-axis
    
    records.append([pid, preg, gluc, bp, skin, insulin, bmi, pedi, age, outcome])

with open('diabetes_temp.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(headers)
    writer.writerows(records)
"

# Move generated file to target Windows directory
# Convert linux path of generated file to windows format if necessary, or just read it in PS
powershell.exe -Command "Move-Item -Path 'diabetes_temp.csv' -Destination '$CSV_PATH_WIN' -Force"

echo "Dataset created at $CSV_PATH_WIN"

# Start Epi Info 7
echo "Starting Epi Info 7..."
# Kill any existing instances
powershell.exe -Command "Stop-Process -Name 'EpiInfo' -ErrorAction SilentlyContinue"
powershell.exe -Command "Stop-Process -Name 'Dashboard' -ErrorAction SilentlyContinue"

# Start the application
# Assuming standard installation path. If it varies, the pre-start hook of env should have handled install.
# We try common paths.
EPI_PATH="C:\\Epi_Info_7\\EpiInfo.exe"
powershell.exe -Command "
if (Test-Path '$EPI_PATH') {
    Start-Process '$EPI_PATH'
} else {
    Write-Host 'Epi Info executable not found at standard location, trying search...'
    \$path = Get-ChildItem -Path C:\\ -Filter EpiInfo.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (\$path) {
        Start-Process \$path.FullName
    }
}
"

# Wait for window
echo "Waiting for Epi Info window..."
for i in {1..30}; do
    # Check via powershell if process is running
    if powershell.exe -Command "Get-Process EpiInfo -ErrorAction SilentlyContinue" | grep -q "EpiInfo"; then
        echo "Epi Info process detected"
        break
    fi
    sleep 1
done

sleep 5

# Maximize Window (using a Powershell script to access User32.dll or similar, 
# but simpler to use nircmd or just let the agent handle it. 
# Here we try to ensure it's foreground).
powershell.exe -Command "
\$wshell = New-Object -ComObject wscript.shell;
\$wshell.AppActivate('Epi Info');
Start-Sleep -Seconds 1
"

# Take initial screenshot using standard tool in env or Powershell
powershell.exe -Command "
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$screen = [System.Windows.Forms.Screen]::PrimaryScreen
\$bitmap = New-Object System.Drawing.Bitmap \$screen.Bounds.Width, \$screen.Bounds.Height
\$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
\$graphics.CopyFromScreen(\$screen.Bounds.X, \$screen.Bounds.Y, 0, 0, \$bitmap.Size)
\$bitmap.Save('C:\\Users\\Docker\\AppData\\Local\\Temp\\task_initial.png')
"
# Copy screenshot to Linux side /tmp for framework
cp "/mnt/c/Users/Docker/AppData/Local/Temp/task_initial.png" /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
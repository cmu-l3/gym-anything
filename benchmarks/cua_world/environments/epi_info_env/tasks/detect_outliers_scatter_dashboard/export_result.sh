#!/bin/bash
echo "=== Exporting task results ==="

# Define paths
DATA_DIR_WIN="C:\\Users\\Docker\\Documents\\DiabetesData"
REPORT_PATH_WIN="$DATA_DIR_WIN\\outlier_report.txt"
CANVAS_PATH_WIN="$DATA_DIR_WIN\\qa_dashboard.canvas7"

# Define Linux mount paths (assuming /mnt/c or similar availability, otherwise we use PowerShell to read)
# We will use PowerShell to read file attributes and content to ensure compatibility
# and output a JSON for the python verifier.

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Use PowerShell to gather evidence
powershell.exe -Command "
\$reportPath = '$REPORT_PATH_WIN'
\$canvasPath = '$CANVAS_PATH_WIN'
\$taskStart = $TASK_START

\$reportExists = Test-Path \$reportPath
\$canvasExists = Test-Path \$canvasPath

\$reportContent = ''
\$reportCreatedDuringTask = \$false
\$canvasCreatedDuringTask = \$false

if (\$reportExists) {
    \$reportContent = Get-Content \$reportPath -Raw
    \$info = Get-Item \$reportPath
    \$creationTime = \$info.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
    \$writeTime = \$info.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
    
    # Simple check: if file modification time > task start
    # Note: comparing unix timestamp requires conversion, simpler to assume true if exists 
    # for this demo or do math in PS.
    \$unixTime = (Get-Item \$reportPath).LastWriteTime.ToUniversalTime() - (Get-Date '1970-01-01').ToUniversalTime()
    \$ts = \$unixTime.TotalSeconds
    if (\$ts -gt \$taskStart) { \$reportCreatedDuringTask = \$true }
}

if (\$canvasExists) {
    \$unixTime = (Get-Item \$canvasPath).LastWriteTime.ToUniversalTime() - (Get-Date '1970-01-01').ToUniversalTime()
    \$ts = \$unixTime.TotalSeconds
    if (\$ts -gt \$taskStart) { \$canvasCreatedDuringTask = \$true }
}

# Create JSON object
\$result = @{
    report_exists = \$reportExists
    canvas_exists = \$canvasExists
    report_content = \$reportContent
    report_created_during = \$reportCreatedDuringTask
    canvas_created_during = \$canvasCreatedDuringTask
    task_end = $TASK_END
}

\$result | ConvertTo-Json -Depth 2 | Out-File 'C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result_win.json' -Encoding ascii
"

# Copy result from Windows temp to Linux temp
# Assuming /mnt/c structure works or we cat the file via powershell
powershell.exe -Command "Get-Content 'C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result_win.json'" > /tmp/task_result.json

# Capture final screenshot
powershell.exe -Command "
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$screen = [System.Windows.Forms.Screen]::PrimaryScreen
\$bitmap = New-Object System.Drawing.Bitmap \$screen.Bounds.Width, \$screen.Bounds.Height
\$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
\$graphics.CopyFromScreen(\$screen.Bounds.X, \$screen.Bounds.Y, 0, 0, \$bitmap.Size)
\$bitmap.Save('C:\\Users\\Docker\\AppData\\Local\\Temp\\task_final.png')
"
cp "/mnt/c/Users/Docker/AppData/Local/Temp/task_final.png" /tmp/task_final.png 2>/dev/null || true

echo "Result JSON content:"
cat /tmp/task_result.json

echo "=== Export complete ==="
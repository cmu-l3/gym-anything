#!/bin/bash
echo "=== Exporting change_room_ceiling_height results ==="

# 1. Capture final screenshot
powershell -Command "
Add-Type -AssemblyName System.Windows.Forms;
Add-Type -AssemblyName System.Drawing;
$screen = [System.Windows.Forms.Screen]::PrimaryScreen;
$bitmap = New-Object System.Drawing.Bitmap $screen.Bounds.Width, $screen.Bounds.Height;
$graphics = [System.Drawing.Graphics]::FromImage($bitmap);
$graphics.CopyFromScreen($screen.Bounds.Location, [System.Drawing.Point]::Empty, $screen.Bounds.Size);
$bitmap.Save('C:\tmp\task_final.png');
$graphics.Dispose();
$bitmap.Dispose();
"

# 2. Collect verification data (Project file timestamps)
# We look for .dpp files modified AFTER the task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

cat << PS_EOF > /tmp/check_results.ps1
$taskStart = $TASK_START
$docsPath = [Environment]::GetFolderPath("MyDocuments")
$searchPath = Join-Path $docsPath "DreamPlan Projects"

# Also check default save location if distinct
$pathsToCheck = @($docsPath, $searchPath, "C:\Users\Docker\Documents")
$modifiedFiles = @()

foreach ($path in $pathsToCheck) {
    if (Test-Path $path) {
        $files = Get-ChildItem -Path $path -Filter "*.dpp" -Recurse -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            # Convert Windows ticks to Unix timestamp
            $unixTime = (Get-Date $file.LastWriteTime -UFormat %s)
            if ($unixTime -gt $taskStart) {
                $modifiedFiles += @{
                    name = $file.Name
                    path = $file.FullName
                    mtime = $unixTime
                }
            }
        }
    }
}

# Output JSON
$result = @{
    task_start = $taskStart
    modified_projects = $modifiedFiles
    screenshot_exists = (Test-Path "C:\tmp\task_final.png")
    app_running = (Get-Process -Name "dreamplan" -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
}

$result | ConvertTo-Json -Depth 3 | Out-File "C:\tmp\task_result.json" -Encoding ascii
PS_EOF

powershell -ExecutionPolicy Bypass -File /tmp/check_results.ps1

# 3. Output result for log
cat /tmp/task_result.json

echo "=== Export complete ==="
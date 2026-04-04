#!/bin/bash
echo "=== Exporting task results ==="

# Define paths
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"
PBIX_PATH="C:\Users\Docker\Desktop\Census_Pyramid.pbix"
# Bash path equivalent
PBIX_BASH_PATH="/c/Users/Docker/Desktop/Census_Pyramid.pbix"

# Use PowerShell to check file properties and take final screenshot
cat <<EOF > /tmp/check_result.ps1
\$pbiPath = "$PBIX_PATH"
\$result = @{
    task_start = $TASK_START
    output_exists = \$false
    file_created_during_task = \$false
    output_size_bytes = 0
}

if (Test-Path \$pbiPath) {
    \$item = Get-Item \$pbiPath
    \$result.output_exists = \$true
    \$result.output_size_bytes = \$item.Length
    
    # Check creation/mod time (Unix timestamp)
    \$creationTime = (Get-Date \$item.CreationTime -UFormat %s)
    \$modTime = (Get-Date \$item.LastWriteTime -UFormat %s)
    
    if (\$creationTime -gt $TASK_START -or \$modTime -gt $TASK_START) {
        \$result.file_created_during_task = \$true
    }
}

# Take final screenshot
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$screen = [System.Windows.Forms.Screen]::PrimaryScreen
\$bitmap = New-Object System.Drawing.Bitmap \$screen.Bounds.Width, \$screen.Bounds.Height
\$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
\$graphics.CopyFromScreen(\$screen.Bounds.X, \$screen.Bounds.Y, 0, 0, \$bitmap.Size)
\$bitmap.Save("C:\\tmp\\task_final.png")
\$result.screenshot_path = "C:\\tmp\\task_final.png"

\$result | ConvertTo-Json | Out-File -FilePath "C:\\tmp\\task_result.json" -Encoding ASCII
EOF

powershell -ExecutionPolicy Bypass -File /tmp/check_result.ps1

# Move result to standard location for verifier
cp /c/tmp/task_result.json "$RESULT_JSON" 2>/dev/null || true
cp /c/tmp/task_final.png /tmp/task_final.png 2>/dev/null || true

# Also copy the PBIX file to /tmp for the verifier to pick up
if [ -f "$PBIX_BASH_PATH" ]; then
    cp "$PBIX_BASH_PATH" /tmp/Census_Pyramid.pbix
    chmod 666 /tmp/Census_Pyramid.pbix
fi

chmod 666 "$RESULT_JSON" 2>/dev/null || true
cat "$RESULT_JSON"
echo "=== Export complete ==="
#!/bin/bash
echo "=== Exporting Task Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_FILE="/tmp/task_result.json"
TARGET_FILE="C:\Users\Docker\Documents\Product_Search_Tool.dva"
TEMP_DVA="/tmp/Product_Search_Tool.dva"

# 1. Check if the DVA file exists using Powershell
echo "Checking for output file..."
FILE_INFO=$(powershell.exe -Command "
    \$path = '$TARGET_FILE'
    if (Test-Path \$path) {
        \$item = Get-Item \$path
        \$creationTime = \$item.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
        \$lastWriteTime = \$item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
        \$size = \$item.Length
        Write-Output \"EXISTS|\$size|\$creationTime|\$lastWriteTime\"
    } else {
        Write-Output 'MISSING'
    }
" | tr -d '\r')

OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [[ "$FILE_INFO" == EXISTS* ]]; then
    OUTPUT_EXISTS="true"
    IFS='|' read -r STATUS SIZE CTIME MTIME <<< "$FILE_INFO"
    OUTPUT_SIZE=$SIZE
    
    # Simple check: if file exists and we are running after start, valid enough for now.
    # (Detailed timestamp parsing in bash vs windows format is fragile, 
    # relying on verifier to check relative timestamps if needed or just presence)
    # But we can try to copy the file for the verifier
    
    # Copy the DVA file to /tmp for the verifier to inspect
    # DVA files are ZIPs, crucial for verification
    cp "$TARGET_FILE" "$TEMP_DVA" 2>/dev/null || powershell.exe -Command "Copy-Item '$TARGET_FILE' '$TEMP_DVA'"
    
    # Set created flag to true if it exists (refinement in verifier)
    FILE_CREATED_DURING_TASK="true"
fi

# 2. Check if App is still running
APP_RUNNING=$(powershell.exe -Command "if (Get-Process -Name 'DVD' -ErrorAction SilentlyContinue) { Write-Host 'true' } else { Write-Host 'false' }" | tr -d '\r')

# 3. Take final screenshot
if command -v scrot >/dev/null 2>&1; then
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
fi

# 4. Generate Result JSON
cat > "$RESULT_FILE" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$TARGET_FILE",
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "dva_file_available": $([ -f "$TEMP_DVA" ] && echo "true" || echo "false")
}
EOF

# Ensure the temp DVA file is readable
chmod 644 "$TEMP_DVA" 2>/dev/null || true
chmod 644 "$RESULT_FILE" 2>/dev/null || true

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export Complete ==="
#!/bin/bash
echo "=== Exporting task results ==="

# 1. Record Timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Gracefully Close JStock (Ensures data is flushed to disk)
# Try Alt+F4 first to trigger save
DISPLAY=:1 xdotool search --name "JStock" windowactivate --sync key --clearmodifiers alt+F4 2>/dev/null || true
sleep 3
# If "Save?" dialog appears, press Enter
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 2
# Force kill if still running
pkill -f "jstock.jar" 2>/dev/null || true

# 3. Locate Portfolio File
PORTFOLIO_FILE="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/buyportfolio.csv"

# 4. Check File Stats
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$PORTFOLIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$PORTFOLIO_FILE")
    FILE_MTIME=$(stat -c %Y "$PORTFOLIO_FILE")
    
    # Check if modified after task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Copy file to /tmp for easy extraction by verifier
    cp "$PORTFOLIO_FILE" /tmp/buyportfolio_export.csv
    chmod 666 /tmp/buyportfolio_export.csv
else
    echo "WARNING: Portfolio file not found at $PORTFOLIO_FILE"
fi

# 5. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 6. Create Metadata JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "csv_export_path": "/tmp/buyportfolio_export.csv",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
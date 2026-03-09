#!/bin/bash
echo "=== Exporting Consolidate Portfolios Result ==="

# Paths
MASTER_CSV="/home/ga/.jstock/1.0.7/UnitedState/portfolios/Master/buyportfolio.csv"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check file status
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$MASTER_CSV" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$MASTER_CSV")
    FILE_MTIME=$(stat -c %Y "$MASTER_CSV")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Copy the CSV to temp location for the verifier to read via copy_from_env
    cp "$MASTER_CSV" /tmp/master_buyportfolio.csv
    chmod 666 /tmp/master_buyportfolio.csv
else
    echo "WARNING: Master portfolio CSV not found at $MASTER_CSV"
fi

# Check if JStock is running
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "output_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "output_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "csv_path_internal": "/tmp/master_buyportfolio.csv"
}
EOF

chmod 666 /tmp/task_result.json

echo "Export complete. Result JSON:"
cat /tmp/task_result.json
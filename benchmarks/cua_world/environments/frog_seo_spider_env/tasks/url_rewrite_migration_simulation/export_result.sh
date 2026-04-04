#!/bin/bash
# Export result script for URL Rewrite Migration Simulation

source /workspace/scripts/task_utils.sh

echo "=== Exporting URL Rewrite Results ==="

# Trap errors
trap 'ensure_result_file /tmp/task_result.json "export script error: $?"' ERR

# 1. Capture final visual state
take_screenshot /tmp/task_final.png

# 2. Variables
EXPORT_PATH="/home/ga/Documents/SEO/exports/migration_simulation.csv"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0
ROW_COUNT=0
SF_RUNNING="false"

# 3. Check Application State
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# 4. Check Output File
if [ -f "$EXPORT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$EXPORT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
    
    # Verify timestamp
    if [ "$FILE_MTIME" -gt "$TASK_START_EPOCH" ]; then
        FILE_CREATED_DURING_TASK="true"
        
        # Count rows (excluding header)
        ROW_COUNT=$(($(wc -l < "$EXPORT_PATH") - 1))
    fi
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sf_running": $SF_RUNNING,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_path": "$EXPORT_PATH",
    "file_size_bytes": $FILE_SIZE,
    "row_count": $ROW_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# 6. Save JSON
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="
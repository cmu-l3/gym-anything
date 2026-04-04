#!/bin/bash
echo "=== Exporting consolidate_genres result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Kill LibreOffice to ensure buffers are flushed to disk (HSQLDB writes on close/save)
kill_libreoffice

# Paths
ODB_PATH="/home/ga/chinook.odb"
CSV_PATH="/home/ga/Documents/heavy_music_tracks.csv"
RESULT_JSON="/tmp/task_result.json"

# Check ODB modification
ODB_MODIFIED="false"
if [ -f "$ODB_PATH" ]; then
    INITIAL_MTIME=$(cat /tmp/initial_odb_mtime.txt 2>/dev/null || echo "0")
    CURRENT_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    
    # Check if modified after start and different from initial
    if [ "$CURRENT_MTIME" -gt "$TASK_START" ] && [ "$CURRENT_MTIME" != "$INITIAL_MTIME" ]; then
        ODB_MODIFIED="true"
    fi
fi

# Check CSV Export
CSV_EXISTS="false"
CSV_SIZE="0"
CSV_ROWS="0"
if [ -f "$CSV_PATH" ]; then
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_EXISTS="true"
        CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
        # Count non-empty lines
        CSV_ROWS=$(grep -cve '^\s*$' "$CSV_PATH" || echo "0")
    fi
fi

# Create result JSON
# We don't verify content here; we ship files to the python verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_exists": $([ -f "$ODB_PATH" ] && echo "true" || echo "false"),
    "odb_modified": $ODB_MODIFIED,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to final location
rm -f "$RESULT_JSON" 2>/dev/null || sudo rm -f "$RESULT_JSON" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_JSON"
chmod 666 "$RESULT_JSON"
rm -f "$TEMP_JSON"

# Ensure artifacts are readable by the verifier (agent user owns them)
chmod 644 "$ODB_PATH" 2>/dev/null || true
chmod 644 "$CSV_PATH" 2>/dev/null || true

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="
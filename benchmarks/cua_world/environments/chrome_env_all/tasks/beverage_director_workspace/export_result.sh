#!/bin/bash
set -euo pipefail

echo "=== Exporting Beverage Director Workspace Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot BEFORE closing Chrome (to capture UI state)
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Gracefully close Chrome to force data flush to Preferences, Bookmarks, Web Data, Local State
echo "Closing Chrome to flush SQLite and JSON files..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 2

# Check if the required Tech_Sheets directory was created
DIR_EXISTS="false"
if [ -d "/home/ga/Documents/Tech_Sheets" ]; then
    DIR_EXISTS="true"
fi

# Write system state wrapper for the verifier
TEMP_JSON=$(mktemp /tmp/task_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "tech_sheets_dir_exists": $DIR_EXISTS,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to standard location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
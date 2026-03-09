#!/bin/bash
set -euo pipefail

echo "=== Exporting Set Flap Deflection result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# Paths
ORIGINAL_FILE="/home/ga/Documents/airfoils/naca4415_original.dat"
MODIFIED_FILE="/home/ga/Documents/airfoils/naca4415_flap10.dat"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check Original File
ORIG_EXISTS="false"
ORIG_SIZE="0"
ORIG_CREATED_DURING="false"

if [ -f "$ORIGINAL_FILE" ]; then
    ORIG_EXISTS="true"
    ORIG_SIZE=$(stat -c%s "$ORIGINAL_FILE")
    ORIG_MTIME=$(stat -c%Y "$ORIGINAL_FILE")
    if [ "$ORIG_MTIME" -gt "$TASK_START" ]; then
        ORIG_CREATED_DURING="true"
    fi
fi

# Check Modified File
MOD_EXISTS="false"
MOD_SIZE="0"
MOD_CREATED_DURING="false"

if [ -f "$MODIFIED_FILE" ]; then
    MOD_EXISTS="true"
    MOD_SIZE=$(stat -c%s "$MODIFIED_FILE")
    MOD_MTIME=$(stat -c%Y "$MODIFIED_FILE")
    if [ "$MOD_MTIME" -gt "$TASK_START" ]; then
        MOD_CREATED_DURING="true"
    fi
fi

# Check if QBlade was running
QBLADE_RUNNING=$(is_qblade_running)
APP_RUNNING="false"
if [ "$QBLADE_RUNNING" -gt 0 ]; then
    APP_RUNNING="true"
fi

# Prepare JSON result
# We construct JSON manually to avoid dependencies, then use temp file swap
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "app_was_running": $APP_RUNNING,
    "original_file": {
        "exists": $ORIG_EXISTS,
        "path": "$ORIGINAL_FILE",
        "size_bytes": $ORIG_SIZE,
        "created_during_task": $ORIG_CREATED_DURING
    },
    "modified_file": {
        "exists": $MOD_EXISTS,
        "path": "$MODIFIED_FILE",
        "size_bytes": $MOD_SIZE,
        "created_during_task": $MOD_CREATED_DURING
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
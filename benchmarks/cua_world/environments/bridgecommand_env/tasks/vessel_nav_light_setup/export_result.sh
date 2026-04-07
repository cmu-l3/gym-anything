#!/bin/bash
echo "=== Exporting Vessel Nav Light Setup Result ==="

MODEL_DIR="/opt/bridgecommand/Models/Othership/PilotBoat_ORC"
CONFIG_FILE="$MODEL_DIR/boat.ini"
TRUTH_FILE="/tmp/nav_light_ground_truth.json"

# Timestamp checks
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
FILE_MODIFIED="false"

if [ -f "$CONFIG_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare export package
# We copy the modified config and the ground truth to a location verify.py can access via copy_from_env
cp "$CONFIG_FILE" /tmp/boat_submitted.ini 2>/dev/null || touch /tmp/boat_submitted.ini
cp "$TRUTH_FILE" /tmp/ground_truth.json 2>/dev/null || echo "{}" > /tmp/ground_truth.json

# Create result metadata
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_modified": $FILE_MODIFIED,
    "config_path": "$CONFIG_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Export complete. Files ready in /tmp/"
ls -l /tmp/boat_submitted.ini /tmp/ground_truth.json /tmp/task_result.json
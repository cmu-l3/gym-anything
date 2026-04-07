#!/bin/bash
echo "=== Exporting task results ==="

# Define paths
OUTPUT_DIR="/home/ga/OpenToonz/output/drift"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check for specific output files
# OpenToonz usually appends frame numbers like "name.0020.png" or just "name0020.png" depending on settings.
# The task asks for "frame0020.png".
# We will search broadly to be robust to naming conventions.

F20_PATH=""
F60_PATH=""

# Find Frame 20 candidate
# Look for *20.png or *0020.png
F20_CANDIDATE=$(find "$OUTPUT_DIR" -name "*20.png" -type f | head -n 1)
if [ -n "$F20_CANDIDATE" ]; then
    F20_PATH="$F20_CANDIDATE"
fi

# Find Frame 60 candidate
F60_CANDIDATE=$(find "$OUTPUT_DIR" -name "*60.png" -type f | head -n 1)
if [ -n "$F60_CANDIDATE" ]; then
    F60_PATH="$F60_CANDIDATE"
fi

# Check timestamps
F20_CREATED_DURING_TASK="false"
F60_CREATED_DURING_TASK="false"

if [ -n "$F20_PATH" ]; then
    MTIME=$(stat -c %Y "$F20_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        F20_CREATED_DURING_TASK="true"
    fi
fi

if [ -n "$F60_PATH" ]; then
    MTIME=$(stat -c %Y "$F60_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        F60_CREATED_DURING_TASK="true"
    fi
fi

# Prepare JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "frame_20_path": "$F20_PATH",
    "frame_60_path": "$F60_PATH",
    "frame_20_exists": $([ -n "$F20_PATH" ] && echo "true" || echo "false"),
    "frame_60_exists": $([ -n "$F60_PATH" ] && echo "true" || echo "false"),
    "frame_20_fresh": $F20_CREATED_DURING_TASK,
    "frame_60_fresh": $F60_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json
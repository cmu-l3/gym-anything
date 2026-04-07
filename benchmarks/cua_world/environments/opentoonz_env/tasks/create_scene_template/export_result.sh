#!/bin/bash
echo "=== Exporting create_scene_template results ==="

# Paths
TARGET_DIR="/home/ga/OpenToonz/projects/ep01_sc010"
TNZ_FILE="$TARGET_DIR/ep01_sc010.tnz"
REPORT_FILE="$TARGET_DIR/scene_specs.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check Scene File (.tnz)
TNZ_EXISTS="false"
TNZ_CREATED_DURING_TASK="false"
TNZ_CONTENT_PREVIEW=""
TNZ_SIZE="0"
DETECTED_WIDTH=""
DETECTED_HEIGHT=""
DETECTED_FPS=""

if [ -f "$TNZ_FILE" ]; then
    TNZ_EXISTS="true"
    TNZ_SIZE=$(stat -c %s "$TNZ_FILE")
    TNZ_MTIME=$(stat -c %Y "$TNZ_FILE")
    
    if [ "$TNZ_MTIME" -gt "$TASK_START" ]; then
        TNZ_CREATED_DURING_TASK="true"
    fi

    # Try to extract specs from TNZ (XML-like format)
    # Looking for cameraRes value="1280 720" or info w="1280" h="720"
    # Looking for fps value="24"
    
    # Read first 500 lines to avoid massive files
    TNZ_CONTENT_PREVIEW=$(head -n 500 "$TNZ_FILE" | base64 -w 0)
    
    # Simple grep extraction for bash-level debugging (Python will do heavy lifting)
    DETECTED_FPS=$(grep -o 'fps value="[0-9]*"' "$TNZ_FILE" | grep -o '[0-9]*' | head -1 || echo "")
    # Resolution usually appears as 'value="1280 720"' in cameraRes or w="1280" h="720"
    DETECTED_WIDTH=$(grep -o 'w="[0-9]*"' "$TNZ_FILE" | grep -o '[0-9]*' | head -1 || echo "")
    DETECTED_HEIGHT=$(grep -o 'h="[0-9]*"' "$TNZ_FILE" | grep -o '[0-9]*' | head -1 || echo "")
fi

# 2. Check Report File (.txt)
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    REPORT_CONTENT=$(cat "$REPORT_FILE" | base64 -w 0)
fi

# 3. Check Application State
APP_RUNNING="false"
if pgrep -f "opentoonz" > /dev/null; then
    APP_RUNNING="true"
fi

WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "opentoonz" | awk '{$1=$2=$3=$4=""; print $0}' | sed 's/^[ \t]*//' || echo "")

# Export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "tnz_exists": $TNZ_EXISTS,
    "tnz_created_during_task": $TNZ_CREATED_DURING_TASK,
    "tnz_size_bytes": $TNZ_SIZE,
    "tnz_content_base64": "$TNZ_CONTENT_PREVIEW",
    "detected_fps_grep": "$DETECTED_FPS",
    "detected_width_grep": "$DETECTED_WIDTH",
    "detected_height_grep": "$DETECTED_HEIGHT",
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_base64": "$REPORT_CONTENT",
    "app_running": $APP_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
#!/bin/bash
echo "=== Exporting Line-of-Sight Analysis Results ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# ================================================================
# Check KML file
# ================================================================
KML_PATH="/home/ga/Documents/microwave_link_analysis.kml"
KML_EXISTS="false"
KML_CREATED_DURING_TASK="false"
KML_SIZE="0"
KML_CONTENT=""

if [ -f "$KML_PATH" ]; then
    KML_EXISTS="true"
    KML_SIZE=$(stat -c %s "$KML_PATH" 2>/dev/null || echo "0")
    KML_MTIME=$(stat -c %Y "$KML_PATH" 2>/dev/null || echo "0")
    
    if [ "$KML_MTIME" -gt "$TASK_START" ]; then
        KML_CREATED_DURING_TASK="true"
    fi
    
    # Extract KML content for verification (first 10000 chars)
    KML_CONTENT=$(head -c 10000 "$KML_PATH" 2>/dev/null | base64 -w 0 || echo "")
fi

# ================================================================
# Check Screenshot file
# ================================================================
SCREENSHOT_PATH="/home/ga/Documents/los_profile.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"
SCREENSHOT_SIZE="0"
SCREENSHOT_WIDTH="0"
SCREENSHOT_HEIGHT="0"

if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    SCREENSHOT_MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
    
    # Get image dimensions using Python/PIL
    DIMENSIONS=$(python3 << 'PYEOF' 2>/dev/null || echo '{"width": 0, "height": 0}'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/Documents/los_profile.png")
    print(json.dumps({"width": img.width, "height": img.height, "format": img.format or "unknown"}))
except Exception as e:
    print(json.dumps({"width": 0, "height": 0, "format": "error", "error": str(e)}))
PYEOF
)
    SCREENSHOT_WIDTH=$(echo "$DIMENSIONS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    SCREENSHOT_HEIGHT=$(echo "$DIMENSIONS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
fi

# ================================================================
# Check Report file
# ================================================================
REPORT_PATH="/home/ga/Documents/los_report.txt"
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_SIZE="0"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Get report content (base64 encoded for safe JSON)
    REPORT_CONTENT=$(cat "$REPORT_PATH" 2>/dev/null | base64 -w 0 || echo "")
fi

# ================================================================
# Check Google Earth state
# ================================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

GE_WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "")

# ================================================================
# Create JSON result
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "duration_seconds": $((TASK_END - TASK_START)),
    "kml": {
        "exists": $KML_EXISTS,
        "created_during_task": $KML_CREATED_DURING_TASK,
        "size_bytes": $KML_SIZE,
        "content_base64": "$KML_CONTENT"
    },
    "screenshot": {
        "exists": $SCREENSHOT_EXISTS,
        "created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
        "size_bytes": $SCREENSHOT_SIZE,
        "width": $SCREENSHOT_WIDTH,
        "height": $SCREENSHOT_HEIGHT
    },
    "report": {
        "exists": $REPORT_EXISTS,
        "created_during_task": $REPORT_CREATED_DURING_TASK,
        "size_bytes": $REPORT_SIZE,
        "content_base64": "$REPORT_CONTENT"
    },
    "google_earth": {
        "running": $GE_RUNNING,
        "window_title": "$GE_WINDOW_TITLE"
    },
    "final_screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/task_result.json"
echo "--- Summary ---"
echo "KML file: exists=$KML_EXISTS, created_during_task=$KML_CREATED_DURING_TASK, size=$KML_SIZE"
echo "Screenshot: exists=$SCREENSHOT_EXISTS, created_during_task=$SCREENSHOT_CREATED_DURING_TASK, size=$SCREENSHOT_SIZE"
echo "Report: exists=$REPORT_EXISTS, created_during_task=$REPORT_CREATED_DURING_TASK, size=$REPORT_SIZE"
echo "Google Earth: running=$GE_RUNNING"
echo "=== Export complete ==="
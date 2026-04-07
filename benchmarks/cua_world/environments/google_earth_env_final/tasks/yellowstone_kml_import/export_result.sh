#!/bin/bash
set -e
echo "=== Exporting Yellowstone KML Import Result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot FIRST (before any other operations)
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_final_screenshot.png ]; then
    FINAL_SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_screenshot.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SCREENSHOT_SIZE} bytes"
else
    FINAL_SCREENSHOT_SIZE="0"
    echo "WARNING: Could not capture final screenshot"
fi

# ================================================================
# Check KML file access time (was it opened?)
# ================================================================
KML_PATH="/home/ga/Documents/grand_prismatic_trail.kml"
KML_INITIAL_ATIME=$(cat /tmp/kml_initial_atime.txt 2>/dev/null || echo "0")
KML_ACCESSED="false"

if [ -f "$KML_PATH" ]; then
    KML_CURRENT_ATIME=$(stat -c %X "$KML_PATH" 2>/dev/null || echo "0")
    if [ "$KML_CURRENT_ATIME" -gt "$KML_INITIAL_ATIME" ]; then
        KML_ACCESSED="true"
    fi
    # Also check if accessed after task start
    if [ "$KML_CURRENT_ATIME" -gt "$TASK_START" ]; then
        KML_ACCESSED="true"
    fi
else
    KML_CURRENT_ATIME="0"
fi

# ================================================================
# Check screenshot output file
# ================================================================
SCREENSHOT_PATH="/home/ga/Documents/grand_prismatic_imported.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"
SCREENSHOT_SIZE="0"
SCREENSHOT_WIDTH="0"
SCREENSHOT_HEIGHT="0"

if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    SCREENSHOT_SIZE=$(stat -c %s "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
    
    # Get image dimensions using Python/PIL
    DIMENSIONS=$(python3 << 'PYEOF' 2>/dev/null || echo '{"width": 0, "height": 0}')
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/Documents/grand_prismatic_imported.png")
    print(json.dumps({"width": img.width, "height": img.height, "format": img.format or "unknown"}))
except Exception as e:
    print(json.dumps({"width": 0, "height": 0, "format": "error", "error": str(e)}))
PYEOF
    
    SCREENSHOT_WIDTH=$(echo "$DIMENSIONS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    SCREENSHOT_HEIGHT=$(echo "$DIMENSIONS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
fi

# ================================================================
# Check Google Earth myplaces.kml for import evidence
# ================================================================
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"
MYPLACES_INITIAL_MTIME=$(cat /tmp/myplaces_initial_mtime.txt 2>/dev/null || echo "0")
MYPLACES_INITIAL_SIZE=$(cat /tmp/myplaces_initial_size.txt 2>/dev/null || echo "0")
MYPLACES_MODIFIED="false"
IMPORT_EVIDENCE="false"

if [ -f "$MYPLACES_PATH" ]; then
    MYPLACES_CURRENT_MTIME=$(stat -c %Y "$MYPLACES_PATH" 2>/dev/null || echo "0")
    MYPLACES_CURRENT_SIZE=$(stat -c %s "$MYPLACES_PATH" 2>/dev/null || echo "0")
    
    # Check if modified
    if [ "$MYPLACES_CURRENT_MTIME" -gt "$MYPLACES_INITIAL_MTIME" ] || \
       [ "$MYPLACES_CURRENT_SIZE" -ne "$MYPLACES_INITIAL_SIZE" ]; then
        MYPLACES_MODIFIED="true"
    fi
    
    # Check content for evidence of import
    if grep -qi "grand prismatic\|yellowstone\|trailhead\|boardwalk" "$MYPLACES_PATH" 2>/dev/null; then
        IMPORT_EVIDENCE="true"
    fi
fi

# ================================================================
# Check if Google Earth is still running
# ================================================================
GE_RUNNING="false"
if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

# Get Google Earth window info
GE_WINDOW_TITLE=""
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

# ================================================================
# Check Google Earth cache for recent activity
# ================================================================
CACHE_ACTIVITY="false"
CACHE_DIR="/home/ga/.googleearth/Cache"
if [ -d "$CACHE_DIR" ]; then
    # Check if any cache files were modified during task
    RECENT_CACHE=$(find "$CACHE_DIR" -type f -newer /tmp/task_start_time.txt 2>/dev/null | wc -l || echo "0")
    if [ "$RECENT_CACHE" -gt "0" ]; then
        CACHE_ACTIVITY="true"
    fi
fi

# ================================================================
# Create JSON result file
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    
    "kml_file": {
        "path": "$KML_PATH",
        "accessed": $KML_ACCESSED,
        "initial_atime": $KML_INITIAL_ATIME,
        "current_atime": $KML_CURRENT_ATIME
    },
    
    "screenshot": {
        "path": "$SCREENSHOT_PATH",
        "exists": $SCREENSHOT_EXISTS,
        "created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
        "size_bytes": $SCREENSHOT_SIZE,
        "width": $SCREENSHOT_WIDTH,
        "height": $SCREENSHOT_HEIGHT
    },
    
    "google_earth": {
        "running": $GE_RUNNING,
        "window_title": "$GE_WINDOW_TITLE",
        "myplaces_modified": $MYPLACES_MODIFIED,
        "import_evidence": $IMPORT_EVIDENCE,
        "cache_activity": $CACHE_ACTIVITY
    },
    
    "final_screenshot_path": "/tmp/task_final_screenshot.png",
    "final_screenshot_size": $FINAL_SCREENSHOT_SIZE
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Results ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="
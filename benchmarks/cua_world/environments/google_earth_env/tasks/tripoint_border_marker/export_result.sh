#!/bin/bash
set -euo pipefail

echo "=== Exporting tripoint_border_marker task result ==="

export DISPLAY=${DISPLAY:-:1}

# ============================================================
# Record task end time
# ============================================================
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DURATION=$((TASK_END - TASK_START))

echo "Task duration: ${DURATION} seconds"

# ============================================================
# Take final screenshot
# ============================================================
scrot /tmp/task_final_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_final_screenshot.png ]; then
    SIZE=$(stat -c %s /tmp/task_final_screenshot.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# ============================================================
# Check myplaces.kml for new placemarks
# ============================================================
EARTH_CONFIG_DIR="/home/ga/.googleearth"
MY_PLACES_FILE="$EARTH_CONFIG_DIR/myplaces.kml"

# Get initial counts
INITIAL_COUNT=$(cat /tmp/initial_placemark_count.txt 2>/dev/null || echo "0")
INITIAL_HASH=$(cat /tmp/initial_myplaces_hash.txt 2>/dev/null || echo "none")

# Current state
MYPLACES_EXISTS="false"
CURRENT_COUNT="0"
CURRENT_HASH="none"
FILE_MODIFIED="false"
FILE_MTIME="0"
PLACEMARK_ADDED="false"
MYPLACES_CONTENT=""

if [ -f "$MY_PLACES_FILE" ]; then
    MYPLACES_EXISTS="true"
    CURRENT_COUNT=$(grep -c "<Placemark>" "$MY_PLACES_FILE" 2>/dev/null || echo "0")
    CURRENT_HASH=$(md5sum "$MY_PLACES_FILE" | cut -d' ' -f1)
    FILE_MTIME=$(stat -c %Y "$MY_PLACES_FILE" 2>/dev/null || echo "0")
    
    # Check if file was modified during task
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Check if new placemark was added
    if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
        PLACEMARK_ADDED="true"
    fi
    
    # Read content for analysis
    MYPLACES_CONTENT=$(cat "$MY_PLACES_FILE" 2>/dev/null | base64 -w 0)
    
    # Copy myplaces.kml for verifier
    cp "$MY_PLACES_FILE" /tmp/myplaces_final.kml 2>/dev/null || true
    chmod 644 /tmp/myplaces_final.kml 2>/dev/null || true
fi

# Also check for any exported KML files in common locations
EXPORTED_KML=""
for dir in "/home/ga" "/home/ga/Desktop" "/home/ga/Documents" "/home/ga/Downloads"; do
    if [ -d "$dir" ]; then
        for kml in "$dir"/*.kml "$dir"/*.kmz; do
            if [ -f "$kml" ] && [ "$kml" != "$MY_PLACES_FILE" ]; then
                KML_MTIME=$(stat -c %Y "$kml" 2>/dev/null || echo "0")
                if [ "$KML_MTIME" -gt "$TASK_START" ]; then
                    EXPORTED_KML="$kml"
                    cp "$kml" /tmp/exported_placemark.kml 2>/dev/null || true
                    break 2
                fi
            fi
        done
    fi
done

# ============================================================
# Check Google Earth process state
# ============================================================
GE_RUNNING="false"
if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

# Get window title for context
WINDOW_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")

# ============================================================
# Create JSON result
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $DURATION,
    "myplaces_exists": $MYPLACES_EXISTS,
    "initial_placemark_count": $INITIAL_COUNT,
    "current_placemark_count": $CURRENT_COUNT,
    "file_modified_during_task": $FILE_MODIFIED,
    "placemark_added": $PLACEMARK_ADDED,
    "file_mtime": $FILE_MTIME,
    "initial_hash": "$INITIAL_HASH",
    "current_hash": "$CURRENT_HASH",
    "exported_kml_path": "$EXPORTED_KML",
    "google_earth_running": $GE_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "myplaces_path": "$MY_PLACES_FILE",
    "myplaces_content_base64": "$MYPLACES_CONTENT"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Summary ==="
echo "Myplaces exists: $MYPLACES_EXISTS"
echo "Initial placemarks: $INITIAL_COUNT"
echo "Current placemarks: $CURRENT_COUNT"
echo "File modified during task: $FILE_MODIFIED"
echo "New placemark added: $PLACEMARK_ADDED"
echo "Google Earth running: $GE_RUNNING"
echo ""
echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="
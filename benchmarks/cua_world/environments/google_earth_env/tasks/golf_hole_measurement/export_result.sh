#!/bin/bash
set -e
echo "=== Exporting Golf Hole Measurement Task Result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot FIRST (before any state changes)
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_state/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_state/task_final.png 2>/dev/null || true

# Check KML file state
KML_PATH="/home/ga/.googleearth/myplaces.kml"
KML_EXISTS="false"
KML_MTIME="0"
KML_SIZE="0"
CURRENT_PLACEMARK_COUNT="0"
CURRENT_PATH_COUNT="0"
KML_CONTENT=""

if [ -f "$KML_PATH" ]; then
    KML_EXISTS="true"
    KML_MTIME=$(stat -c %Y "$KML_PATH" 2>/dev/null || echo "0")
    KML_SIZE=$(stat -c %s "$KML_PATH" 2>/dev/null || echo "0")
    CURRENT_PLACEMARK_COUNT=$(grep -c "<Placemark>" "$KML_PATH" 2>/dev/null || echo "0")
    CURRENT_PATH_COUNT=$(grep -c "<LineString>" "$KML_PATH" 2>/dev/null || echo "0")
    
    # Extract KML content for analysis (limit size)
    KML_CONTENT=$(head -c 50000 "$KML_PATH" 2>/dev/null | base64 -w 0 || echo "")
    
    # Copy KML to tmp for verifier access
    cp "$KML_PATH" /tmp/task_state/myplaces_final.kml 2>/dev/null || true
fi

# Check for any exported KML files in common locations
EXPORTED_KML=""
for dir in "/home/ga" "/home/ga/Desktop" "/home/ga/Documents" "/tmp"; do
    if [ -d "$dir" ]; then
        FOUND=$(find "$dir" -maxdepth 2 -name "*.kml" -newer /tmp/task_start_time.txt 2>/dev/null | head -1)
        if [ -n "$FOUND" ]; then
            EXPORTED_KML="$FOUND"
            cp "$FOUND" /tmp/task_state/exported.kml 2>/dev/null || true
            break
        fi
    fi
done

# Load initial state
INITIAL_PLACEMARK_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/task_state/initial_state.json')).get('initial_placemark_count', 0))" 2>/dev/null || echo "0")
INITIAL_PATH_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/task_state/initial_state.json')).get('initial_path_count', 0))" 2>/dev/null || echo "0")
INITIAL_KML_MTIME=$(python3 -c "import json; print(json.load(open('/tmp/task_state/initial_state.json')).get('initial_kml_mtime', 0))" 2>/dev/null || echo "0")

# Determine if KML was modified
KML_MODIFIED="false"
if [ "$KML_MTIME" -gt "$TASK_START" ]; then
    KML_MODIFIED="true"
fi

# Calculate changes
NEW_PLACEMARKS=$((CURRENT_PLACEMARK_COUNT - INITIAL_PLACEMARK_COUNT))
NEW_PATHS=$((CURRENT_PATH_COUNT - INITIAL_PATH_COUNT))

# Check if Google Earth is still running
GE_RUNNING="false"
GE_PID=""
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f google-earth-pro | head -1)
fi

# Get window information
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
GE_WINDOW_EXISTS="false"
if wmctrl -l 2>/dev/null | grep -qi "Google Earth"; then
    GE_WINDOW_EXISTS="true"
fi

# Check for ruler/measurement tool usage via window titles
RULER_WINDOW_VISIBLE="false"
if wmctrl -l 2>/dev/null | grep -qi "Ruler"; then
    RULER_WINDOW_VISIBLE="true"
fi

# Create JSON result
RESULT_FILE="/tmp/task_result.json"
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    
    "kml_state": {
        "exists": $KML_EXISTS,
        "modified_during_task": $KML_MODIFIED,
        "modification_time": $KML_MTIME,
        "file_size_bytes": $KML_SIZE,
        "current_placemark_count": $CURRENT_PLACEMARK_COUNT,
        "current_path_count": $CURRENT_PATH_COUNT,
        "initial_placemark_count": $INITIAL_PLACEMARK_COUNT,
        "initial_path_count": $INITIAL_PATH_COUNT,
        "new_placemarks": $NEW_PLACEMARKS,
        "new_paths": $NEW_PATHS
    },
    
    "exported_kml": "$EXPORTED_KML",
    
    "google_earth_state": {
        "running": $GE_RUNNING,
        "pid": "$GE_PID",
        "window_exists": $GE_WINDOW_EXISTS,
        "ruler_window_visible": $RULER_WINDOW_VISIBLE,
        "active_window_title": "$WINDOW_TITLE"
    },
    
    "screenshots": {
        "initial": "/tmp/task_state/task_initial.png",
        "final": "/tmp/task_state/task_final.png"
    },
    
    "kml_files": {
        "myplaces": "/tmp/task_state/myplaces_final.kml",
        "exported": "/tmp/task_state/exported.kml"
    }
}
EOF

# Move to final location with proper permissions
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

# Make all state files readable
chmod -R 755 /tmp/task_state 2>/dev/null || true

echo ""
echo "=== Export Results ==="
cat "$RESULT_FILE"
echo ""
echo "=== Export complete ==="
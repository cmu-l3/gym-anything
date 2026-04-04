#!/bin/bash
set -e
echo "=== Exporting UTM Coordinate Navigation task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot FIRST (before any potential app closure)
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    SCREENSHOT_EXISTS="true"
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
else
    SCREENSHOT_EXISTS="false"
    SCREENSHOT_SIZE="0"
    echo "WARNING: Could not capture final screenshot"
fi

# Check configuration files for UTM setting
CONFIG_FILE="/home/ga/.config/Google/GoogleEarthPro.conf"
BACKUP_CONFIG="/home/ga/.googleearth/GoogleEarth.conf"

UTM_ENABLED="false"
CONFIG_FORMAT_VALUE="-1"
CONFIG_MTIME="0"
CONFIG_MODIFIED="false"

# Check primary config file
if [ -f "$CONFIG_FILE" ]; then
    CONFIG_MTIME=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || echo "0")
    
    # Check if modified during task
    if [ "$CONFIG_MTIME" -gt "$TASK_START" ]; then
        CONFIG_MODIFIED="true"
    fi
    
    # Extract LatLonDisplayFormat value
    # 0 = Decimal Degrees, 1 = Degrees Minutes Seconds, 2 = UTM
    FORMAT_LINE=$(grep -E "LatLonDisplayFormat\s*=" "$CONFIG_FILE" 2>/dev/null || echo "")
    if [ -n "$FORMAT_LINE" ]; then
        CONFIG_FORMAT_VALUE=$(echo "$FORMAT_LINE" | grep -oE "[0-9]+" | head -1 || echo "-1")
        if [ "$CONFIG_FORMAT_VALUE" = "2" ]; then
            UTM_ENABLED="true"
        fi
    fi
    
    echo "Config file found: $CONFIG_FILE"
    echo "Format value: $CONFIG_FORMAT_VALUE (2=UTM)"
    echo "Config modified during task: $CONFIG_MODIFIED"
fi

# Also check backup config location
if [ -f "$BACKUP_CONFIG" ] && [ "$UTM_ENABLED" = "false" ]; then
    BACKUP_FORMAT=$(grep -oE "LatLonDisplayFormat\s*=\s*[0-9]+" "$BACKUP_CONFIG" 2>/dev/null | grep -oE "[0-9]+" || echo "-1")
    if [ "$BACKUP_FORMAT" = "2" ]; then
        UTM_ENABLED="true"
        CONFIG_FORMAT_VALUE="$BACKUP_FORMAT"
        echo "UTM enabled in backup config"
    fi
fi

# Check if Google Earth is running
GE_RUNNING="false"
GE_PID=""
if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f "google-earth" | head -1)
fi

# Get window information
WINDOW_TITLE=""
WINDOW_LIST=""
if command -v wmctrl &> /dev/null; then
    WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
    GE_WINDOW=$(echo "$WINDOW_LIST" | grep -i "Google Earth" | head -1 || echo "")
    if [ -n "$GE_WINDOW" ]; then
        WINDOW_TITLE=$(echo "$GE_WINDOW" | cut -d' ' -f5-)
    fi
fi

# Try to extract current view info from myplaces.kml (if available)
CURRENT_LAT="0"
CURRENT_LON="0"
MYPLACES="/home/ga/.googleearth/myplaces.kml"
if [ -f "$MYPLACES" ]; then
    # Try to get LookAt coordinates
    LAT_MATCH=$(grep -oE "<latitude>[-0-9.]+</latitude>" "$MYPLACES" 2>/dev/null | tail -1 | grep -oE "[-0-9.]+" || echo "0")
    LON_MATCH=$(grep -oE "<longitude>[-0-9.]+</longitude>" "$MYPLACES" 2>/dev/null | tail -1 | grep -oE "[-0-9.]+" || echo "0")
    if [ -n "$LAT_MATCH" ] && [ "$LAT_MATCH" != "0" ]; then
        CURRENT_LAT="$LAT_MATCH"
    fi
    if [ -n "$LON_MATCH" ] && [ "$LON_MATCH" != "0" ]; then
        CURRENT_LON="$LON_MATCH"
    fi
fi

# Create result JSON
RESULT_FILE="/tmp/task_result.json"
cat > "$RESULT_FILE" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    
    "config_checks": {
        "utm_enabled": $UTM_ENABLED,
        "config_format_value": $CONFIG_FORMAT_VALUE,
        "config_modified_during_task": $CONFIG_MODIFIED,
        "config_mtime": $CONFIG_MTIME
    },
    
    "application_state": {
        "google_earth_running": $GE_RUNNING,
        "google_earth_pid": "$GE_PID",
        "window_title": "$WINDOW_TITLE"
    },
    
    "view_info": {
        "extracted_lat": $CURRENT_LAT,
        "extracted_lon": $CURRENT_LON
    },
    
    "evidence": {
        "screenshot_exists": $SCREENSHOT_EXISTS,
        "screenshot_size_bytes": $SCREENSHOT_SIZE,
        "screenshot_path": "/tmp/task_final_state.png"
    },
    
    "target": {
        "name": "Devils Tower National Monument",
        "target_lat": 44.5902,
        "target_lon": -104.7146,
        "tolerance_km": 5.0
    }
}
EOF

# Fix JSON boolean values (bash outputs lowercase, need proper JSON)
sed -i 's/: true/: true/g; s/: false/: false/g' "$RESULT_FILE"

# Set permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo ""
echo "=== Export Results ==="
cat "$RESULT_FILE"
echo ""
echo "=== Export complete ==="
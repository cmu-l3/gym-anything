#!/bin/bash
echo "=== Exporting historical_eclipse_planetarium_render results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot BEFORE closing anything (used for VLM verification)
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Gracefully quit KStars to ensure the configuration is flushed to disk
echo "Closing KStars to flush config..."
if command -v qdbus &>/dev/null; then
    DBUS_ADDR="unix:path=/run/user/$(id -u ga)/bus"
    DISPLAY=:1 DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" qdbus org.kde.kstars /MainApplication quit 2>/dev/null || true
fi
sleep 3
# Fallback to wmctrl if it's still running
if pgrep -x "kstars" > /dev/null; then
    DISPLAY=:1 wmctrl -c "KStars" 2>/dev/null || true
    sleep 2
fi

# 3. Read KStars config for location (Lat/Lon)
KSTARSRC="/home/ga/.config/kstarsrc"
LATITUDE=""
LONGITUDE=""

if [ -f "$KSTARSRC" ]; then
    # Look for the [Location] section and extract Latitude and Longitude
    LATITUDE=$(grep -A 15 "\[Location\]" "$KSTARSRC" | grep "^Latitude=" | cut -d'=' -f2 | tr -d '\r')
    LONGITUDE=$(grep -A 15 "\[Location\]" "$KSTARSRC" | grep "^Longitude=" | cut -d'=' -f2 | tr -d '\r')
fi

# Default if not found
if [ -z "$LATITUDE" ]; then LATITUDE="0.0"; fi
if [ -z "$LONGITUDE" ]; then LONGITUDE="0.0"; fi

# 4. Check expected image output
IMAGE_PATH="/home/ga/Documents/sobral_eclipse_1919.png"
IMAGE_EXISTS="false"
IMAGE_MTIME=0
IMAGE_SIZE=0

if [ -f "$IMAGE_PATH" ]; then
    IMAGE_MTIME=$(stat -c %Y "$IMAGE_PATH" 2>/dev/null || echo "0")
    if [ "$IMAGE_MTIME" -gt "$TASK_START" ]; then
        IMAGE_EXISTS="true"
    fi
    IMAGE_SIZE=$(stat -c %s "$IMAGE_PATH" 2>/dev/null || echo "0")
fi

# 5. Check expected text output
TEXT_PATH="/home/ga/Documents/relativity_stars.txt"
TEXT_EXISTS="false"
TEXT_MTIME=0
TEXT_CONTENT_B64=""

if [ -f "$TEXT_PATH" ]; then
    TEXT_MTIME=$(stat -c %Y "$TEXT_PATH" 2>/dev/null || echo "0")
    if [ "$TEXT_MTIME" -gt "$TASK_START" ]; then
        TEXT_EXISTS="true"
    fi
    TEXT_CONTENT_B64=$(head -c 2048 "$TEXT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

# 6. Format booleans for Python interpolation
IMAGE_EXISTS_PY=$([ "$IMAGE_EXISTS" = "true" ] && echo "True" || echo "False")
TEXT_EXISTS_PY=$([ "$TEXT_EXISTS" = "true" ] && echo "True" || echo "False")

# 7. Write result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "kstars_latitude": "$LATITUDE",
    "kstars_longitude": "$LONGITUDE",
    "image_exists": $IMAGE_EXISTS_PY,
    "image_size_bytes": $IMAGE_SIZE,
    "text_exists": $TEXT_EXISTS_PY,
    "text_b64": "$TEXT_CONTENT_B64",
    "final_screenshot_path": "/tmp/task_final.png"
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result written to /tmp/task_result.json"
echo "=== Export complete ==="
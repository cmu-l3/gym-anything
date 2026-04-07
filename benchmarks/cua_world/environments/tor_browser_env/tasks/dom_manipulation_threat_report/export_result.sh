#!/bin/bash
# export_result.sh for dom_manipulation_threat_report task
set -e

echo "=== Exporting dom_manipulation_threat_report results ==="

# 1. Take final screenshot of the state
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TASK_START_TIMESTAMP=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TARGET_FILE="/home/ga/Documents/threat_exhibit.png"

# 2. Check output file
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START_TIMESTAMP" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
fi

echo "Output file exists: $FILE_EXISTS (created during task: $FILE_CREATED_DURING_TASK, size: ${FILE_SIZE} bytes)"

# 3. Analyze output image for DOM modifications (Black background, Red text)
IMAGE_VALID="false"
BLACK_RATIO=0.0
RED_RATIO=0.0
IMAGE_ERROR=""

if [ "$FILE_EXISTS" = "true" ]; then
    echo "Analyzing $TARGET_FILE with Python PIL..."
    IMAGE_ANALYSIS=$(python3 -c '
import sys, json
try:
    from PIL import Image
    img = Image.open("'"$TARGET_FILE"'")
    img = img.convert("RGB")
    
    # Resize to speed up pixel counting
    img.thumbnail((400, 400))
    pixels = img.getdata()
    
    black_count = 0
    red_count = 0
    total = len(pixels)
    
    for r, g, b in pixels:
        # Check for near-pure black (Background)
        if r < 40 and g < 40 and b < 40:
            black_count += 1
        # Check for strong red (Text)
        elif r > 150 and g < 60 and b < 60:
            red_count += 1
            
    print(json.dumps({
        "valid": True,
        "black_ratio": round(black_count / total, 4),
        "red_ratio": round(red_count / total, 4),
        "error": ""
    }))
except Exception as e:
    print(json.dumps({
        "valid": False,
        "black_ratio": 0.0,
        "red_ratio": 0.0,
        "error": str(e)
    }))
' 2>/dev/null || echo '{"valid": false, "black_ratio": 0.0, "red_ratio": 0.0, "error": "Python script failed"}')

    IMAGE_VALID=$(echo "$IMAGE_ANALYSIS" | jq -r '.valid')
    BLACK_RATIO=$(echo "$IMAGE_ANALYSIS" | jq -r '.black_ratio')
    RED_RATIO=$(echo "$IMAGE_ANALYSIS" | jq -r '.red_ratio')
    IMAGE_ERROR=$(echo "$IMAGE_ANALYSIS" | jq -r '.error')
    
    echo "Image Valid: $IMAGE_VALID, Black Ratio: $BLACK_RATIO, Red Ratio: $RED_RATIO"
fi

# 4. Check browsing history for visit to check.torproject.org
VISITED_TARGET="false"
PROFILE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

PLACES_DB="$PROFILE_DIR/places.sqlite"
TEMP_DB="/tmp/places_export.sqlite"

if [ -f "$PLACES_DB" ]; then
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null || true
    [ -f "${PLACES_DB}-wal" ] && cp "${PLACES_DB}-wal" "${TEMP_DB}-wal" 2>/dev/null || true
    [ -f "${PLACES_DB}-shm" ] && cp "${PLACES_DB}-shm" "${TEMP_DB}-shm" 2>/dev/null || true
    
    # Query history after task start
    VISIT_CHECK=$(sqlite3 "$TEMP_DB" "
        SELECT COUNT(*)
        FROM moz_places p
        JOIN moz_historyvisits h ON p.id = h.place_id
        WHERE p.url LIKE '%check.torproject.org%'
        AND (h.visit_date / 1000000) > $TASK_START_TIMESTAMP;
    " 2>/dev/null || echo "0")
    
    if [ "$VISIT_CHECK" -gt "0" ]; then
        VISITED_TARGET="true"
    fi
    echo "Visited target URL: $VISITED_TARGET (Visit count: $VISIT_CHECK)"
    rm -f "$TEMP_DB"* 2>/dev/null || true
fi

# 5. Check if Tor Browser is currently running
TOR_RUNNING="false"
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" > /dev/null; then
    TOR_RUNNING="true"
fi

# 6. Generate final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START_TIMESTAMP,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "image_valid": $IMAGE_VALID,
    "black_pixel_ratio": $BLACK_RATIO,
    "red_pixel_ratio": $RED_RATIO,
    "image_error": "$IMAGE_ERROR",
    "visited_target_url": $VISITED_TARGET,
    "tor_browser_running": $TOR_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json
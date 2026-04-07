#!/bin/bash
set -euo pipefail

echo "=== Exporting terrain_exaggeration_alps task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task timing: start=$TASK_START, end=$TASK_END"

# Take final screenshot
echo "Capturing final state screenshot..."
scrot /tmp/task_final_state.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

# Check output file
OUTPUT_PATH="/home/ga/matterhorn_exaggerated.png"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"
IMAGE_WIDTH="0"
IMAGE_HEIGHT="0"
IMAGE_FORMAT="none"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Get image dimensions using Python/PIL
    DIMENSIONS=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/matterhorn_exaggerated.png")
    print(json.dumps({"width": img.width, "height": img.height, "format": img.format or "unknown"}))
except Exception as e:
    print(json.dumps({"width": 0, "height": 0, "format": "error", "error": str(e)}))
PYEOF
)
    IMAGE_WIDTH=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    IMAGE_HEIGHT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
    IMAGE_FORMAT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('format', 'unknown'))" 2>/dev/null || echo "unknown")
    
    echo "Output file found: ${OUTPUT_SIZE} bytes, ${IMAGE_WIDTH}x${IMAGE_HEIGHT}, format: ${IMAGE_FORMAT}"
else
    echo "Output file NOT found at: $OUTPUT_PATH"
fi

# Check elevation exaggeration setting in config files
EXAGGERATION_VALUE="unknown"
EXAGGERATION_FOUND="false"

CONFIG_PATHS="/home/ga/.config/Google/GoogleEarthPro.conf /home/ga/.googleearth/GoogleEarthPro.conf /home/ga/.googleearth/Registry/google.earth"

for config_path in $CONFIG_PATHS; do
    if [ -f "$config_path" ]; then
        echo "Checking config file: $config_path"
        # Try to extract exaggeration value
        EXTRACTED=$(grep -oiE 'elevationExaggeration[=:][[:space:]]*[0-9.]+' "$config_path" 2>/dev/null | grep -oE '[0-9.]+' | tail -1 || echo "")
        if [ -n "$EXTRACTED" ]; then
            EXAGGERATION_VALUE="$EXTRACTED"
            EXAGGERATION_FOUND="true"
            echo "Found exaggeration value: $EXAGGERATION_VALUE in $config_path"
            break
        fi
        
        # Try alternate patterns
        EXTRACTED=$(grep -oiE 'terrainExaggeration[=:][[:space:]]*[0-9.]+' "$config_path" 2>/dev/null | grep -oE '[0-9.]+' | tail -1 || echo "")
        if [ -n "$EXTRACTED" ]; then
            EXAGGERATION_VALUE="$EXTRACTED"
            EXAGGERATION_FOUND="true"
            echo "Found exaggeration value: $EXAGGERATION_VALUE in $config_path"
            break
        fi
    fi
done

# Also check Google Earth's runtime state if possible
# Google Earth may store the value in binary/SQLite format in newer versions

# Check if Google Earth is running
GE_RUNNING="false"
GE_WINDOW_TITLE=""
if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_WINDOW_TITLE=$(wmctrl -l | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "")
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "image_format": "$IMAGE_FORMAT",
    "exaggeration_found": $EXAGGERATION_FOUND,
    "exaggeration_value": "$EXAGGERATION_VALUE",
    "google_earth_running": $GE_RUNNING,
    "google_earth_window_title": "$GE_WINDOW_TITLE",
    "final_screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Results ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="
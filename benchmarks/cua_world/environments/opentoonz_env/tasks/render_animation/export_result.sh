#!/bin/bash
echo "=== Exporting render_animation task result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

# Check for rendered output
EXPECTED_OUTPUT="/home/ga/OpenToonz/outputs/rendered_animation.mp4"
OUTPUT_DIR="/home/ga/OpenToonz/outputs"

# Initialize result variables
OUTPUT_FOUND="false"
OUTPUT_PATH=""
OUTPUT_SIZE_KB=0
RENDER_SUCCESS="false"

# Check for the expected output file
if [ -f "$EXPECTED_OUTPUT" ]; then
    OUTPUT_FOUND="true"
    OUTPUT_PATH="$EXPECTED_OUTPUT"
    OUTPUT_SIZE_KB=$(du -k "$EXPECTED_OUTPUT" | cut -f1)
    if [ "$OUTPUT_SIZE_KB" -gt 10 ]; then
        RENDER_SUCCESS="true"
    fi
else
    # Look for any MP4 file in outputs directory
    FOUND_MP4=$(find "$OUTPUT_DIR" -name "*.mp4" -type f 2>/dev/null | head -1)
    if [ -n "$FOUND_MP4" ]; then
        OUTPUT_FOUND="true"
        OUTPUT_PATH="$FOUND_MP4"
        OUTPUT_SIZE_KB=$(du -k "$FOUND_MP4" | cut -f1)
        if [ "$OUTPUT_SIZE_KB" -gt 10 ]; then
            RENDER_SUCCESS="true"
        fi
    fi

    # Also check for other video formats that OpenToonz might export
    for ext in avi mov gif; do
        FOUND_VIDEO=$(find "$OUTPUT_DIR" -name "*.$ext" -type f 2>/dev/null | head -1)
        if [ -n "$FOUND_VIDEO" ] && [ "$OUTPUT_FOUND" = "false" ]; then
            OUTPUT_FOUND="true"
            OUTPUT_PATH="$FOUND_VIDEO"
            OUTPUT_SIZE_KB=$(du -k "$FOUND_VIDEO" | cut -f1)
            if [ "$OUTPUT_SIZE_KB" -gt 10 ]; then
                RENDER_SUCCESS="true"
            fi
        fi
    done
fi

# Check OpenToonz window title for scene name
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "opentoonz" | head -1 || echo "")
SCENE_LOADED="false"
if echo "$WINDOW_TITLE" | grep -qi "dwanko\|run\|\.tnz"; then
    SCENE_LOADED="true"
fi

# Get current output file count
CURRENT_COUNT=$(find "$OUTPUT_DIR" -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.mov" -o -name "*.gif" \) 2>/dev/null | wc -l)
INITIAL_COUNT=$(cat /tmp/initial_output_count 2>/dev/null || echo "0")

# Create JSON result in temp file first
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_found": $OUTPUT_FOUND,
    "output_path": "$OUTPUT_PATH",
    "output_size_kb": $OUTPUT_SIZE_KB,
    "render_success": $RENDER_SUCCESS,
    "scene_loaded": $SCENE_LOADED,
    "window_title": "$WINDOW_TITLE",
    "initial_output_count": $INITIAL_COUNT,
    "current_output_count": $CURRENT_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="

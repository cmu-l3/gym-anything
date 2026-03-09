#!/bin/bash
echo "=== Exporting Capture 3D View Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot of Slicer state
echo "Capturing final screenshot..."
take_screenshot /tmp/slicer_3d_final.png ga
sleep 1

# Get screenshot info
SCREENSHOT_DIR=$(get_slicer_screenshot_dir)
FINAL_SCREENSHOT_COUNT=$(ls -1 "$SCREENSHOT_DIR"/*.png 2>/dev/null | wc -l)
INITIAL_SCREENSHOT_COUNT=$(cat /tmp/initial_screenshot_count 2>/dev/null || echo "0")

# Check if new screenshots were created
NEW_SCREENSHOTS=$((FINAL_SCREENSHOT_COUNT - INITIAL_SCREENSHOT_COUNT))
LATEST_SCREENSHOT=""
if [ $NEW_SCREENSHOTS -gt 0 ]; then
    # Get the newest screenshot
    LATEST_SCREENSHOT=$(ls -t "$SCREENSHOT_DIR"/*.png 2>/dev/null | head -1)
fi

# Check final screenshot properties
FINAL_SCREENSHOT="/tmp/slicer_3d_final.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE_KB=0
SCREENSHOT_HAS_3D_CONTENT="false"

if [ -f "$FINAL_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE_KB=$(du -k "$FINAL_SCREENSHOT" 2>/dev/null | cut -f1 || echo "0")

    # 3D rendered screenshots tend to be larger and have more color variety
    # A good 3D render should be >100KB typically
    if [ "$SCREENSHOT_SIZE_KB" -gt 100 ]; then
        SCREENSHOT_HAS_3D_CONTENT="true"
    fi

    # Use ImageMagick to analyze the image
    if command -v identify &> /dev/null; then
        COLORS=$(identify -format "%k" "$FINAL_SCREENSHOT" 2>/dev/null || echo "0")
        # 3D renders typically have many colors (>500)
        if [ "$COLORS" -gt 500 ]; then
            SCREENSHOT_HAS_3D_CONTENT="true"
        fi
    fi
fi

# Also check if user saved a screenshot via Slicer
USER_SCREENSHOT_EXISTS="false"
USER_SCREENSHOT_SIZE_KB=0
if [ -n "$LATEST_SCREENSHOT" ] && [ -f "$LATEST_SCREENSHOT" ]; then
    USER_SCREENSHOT_EXISTS="true"
    USER_SCREENSHOT_SIZE_KB=$(du -k "$LATEST_SCREENSHOT" 2>/dev/null | cut -f1 || echo "0")
    # Copy user's screenshot for verification
    cp "$LATEST_SCREENSHOT" /tmp/slicer_user_screenshot.png 2>/dev/null || true
fi

# Check if Slicer is still running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Check sample file
SAMPLE_FILE="$(get_sample_data_dir)/MRHead.nrrd"
SAMPLE_FILE_EXISTS="false"
if [ -f "$SAMPLE_FILE" ]; then
    SAMPLE_FILE_EXISTS="true"
fi

# Check if data was loaded and possibly 3D rendered
DATA_LOADED="false"
VOLUME_RENDERING_ACTIVE="false"

if [ "$SLICER_RUNNING" = "true" ]; then
    SLICER_PID=$(pgrep -f "Slicer" | head -1)
    if [ -n "$SLICER_PID" ]; then
        # Check if volume rendering module was accessed
        if grep -q "VolumeRendering\|vtkMRMLVolumeRenderingDisplayNode" /proc/$SLICER_PID/maps 2>/dev/null; then
            VOLUME_RENDERING_ACTIVE="true"
        fi
        # Check if sample file was loaded
        if ls -la /proc/$SLICER_PID/fd 2>/dev/null | grep -q "MRHead\|nrrd"; then
            DATA_LOADED="true"
        fi
    fi
fi

# Heuristic: if screenshot is large and colorful, likely has 3D content
if [ "$SCREENSHOT_HAS_3D_CONTENT" = "true" ] || [ "$USER_SCREENSHOT_SIZE_KB" -gt 150 ]; then
    DATA_LOADED="true"
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_kb": $SCREENSHOT_SIZE_KB,
    "screenshot_has_3d_content": $SCREENSHOT_HAS_3D_CONTENT,
    "user_screenshot_exists": $USER_SCREENSHOT_EXISTS,
    "user_screenshot_size_kb": $USER_SCREENSHOT_SIZE_KB,
    "new_screenshots_count": $NEW_SCREENSHOTS,
    "slicer_was_running": $SLICER_RUNNING,
    "sample_file_exists": $SAMPLE_FILE_EXISTS,
    "data_loaded": $DATA_LOADED,
    "volume_rendering_active": $VOLUME_RENDERING_ACTIVE,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/slicer_3d_task_result.json 2>/dev/null || sudo rm -f /tmp/slicer_3d_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/slicer_3d_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/slicer_3d_task_result.json
chmod 666 /tmp/slicer_3d_task_result.json 2>/dev/null || sudo chmod 666 /tmp/slicer_3d_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/slicer_3d_task_result.json"
cat /tmp/slicer_3d_task_result.json
echo ""
echo "=== Export Complete ==="

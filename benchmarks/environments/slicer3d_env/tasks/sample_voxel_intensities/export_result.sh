#!/bin/bash
echo "=== Exporting Sample Voxel Intensities Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_FILE="/home/ga/Documents/SlicerData/intensity_measurements.txt"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
RESULT_DIR="/tmp/task_result"

# Create result directory
mkdir -p "$RESULT_DIR"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot "$RESULT_DIR/final_screenshot.png" 2>/dev/null || \
    take_screenshot "$RESULT_DIR/final_screenshot.png" ga 2>/dev/null || true

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# Check for output file
OUTPUT_EXISTS="false"
OUTPUT_CONTENT=""
OUTPUT_MTIME=0
OUTPUT_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_CONTENT=$(cat "$OUTPUT_FILE" 2>/dev/null | tr '\n' ' ' | sed 's/"/\\"/g' || echo "")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo 0)
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo 0)
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Copy output file to result directory
    cp "$OUTPUT_FILE" "$RESULT_DIR/intensity_measurements.txt" 2>/dev/null || true
fi

echo "Output file exists: $OUTPUT_EXISTS"
echo "File created during task: $FILE_CREATED_DURING_TASK"

# Parse output file for measurements
AORTA_VALUE=""
LIVER_VALUE=""
SPLEEN_VALUE=""
HAS_INTERPRETATION="false"

if [ "$OUTPUT_EXISTS" = "true" ] && [ -n "$OUTPUT_CONTENT" ]; then
    # Extract aorta value
    AORTA_VALUE=$(echo "$OUTPUT_CONTENT" | grep -ioE "aorta[:\s]+([0-9]+\.?[0-9]*)" | grep -oE "[0-9]+\.?[0-9]*" | head -1 || echo "")
    
    # Extract liver value
    LIVER_VALUE=$(echo "$OUTPUT_CONTENT" | grep -ioE "liver[:\s]+([0-9]+\.?[0-9]*)" | grep -oE "[0-9]+\.?[0-9]*" | head -1 || echo "")
    
    # Extract spleen value
    SPLEEN_VALUE=$(echo "$OUTPUT_CONTENT" | grep -ioE "spleen[:\s]+([0-9]+\.?[0-9]*)" | grep -oE "[0-9]+\.?[0-9]*" | head -1 || echo "")
    
    # Check for interpretation
    if echo "$OUTPUT_CONTENT" | grep -qiE "interpretation|normal|expected|range|assessment|finding|conclusion|contrast|enhancement"; then
        HAS_INTERPRETATION="true"
    fi
fi

echo "Parsed values - Aorta: $AORTA_VALUE, Liver: $LIVER_VALUE, Spleen: $SPLEEN_VALUE"
echo "Has interpretation: $HAS_INTERPRETATION"

# Copy ground truth for verification
GT_FILE="$GROUND_TRUTH_DIR/amos_0001_intensity_gt.json"
if [ -f "$GT_FILE" ]; then
    cp "$GT_FILE" "$RESULT_DIR/ground_truth.json" 2>/dev/null || true
fi

# Copy initial and final screenshots
cp /tmp/task_initial_state.png "$RESULT_DIR/initial_screenshot.png" 2>/dev/null || true

# Get window list for evidence
WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null | tr '\n' '; ' || echo "")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "output_file_exists": $OUTPUT_EXISTS,
    "output_file_mtime": $OUTPUT_MTIME,
    "output_file_size": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_content": "$OUTPUT_CONTENT",
    "parsed_aorta_hu": "$AORTA_VALUE",
    "parsed_liver_hu": "$LIVER_VALUE",
    "parsed_spleen_hu": "$SPLEEN_VALUE",
    "has_interpretation": $HAS_INTERPRETATION,
    "windows_list": "$WINDOWS_LIST",
    "screenshot_path": "$RESULT_DIR/final_screenshot.png"
}
EOF

# Move to final locations with permission handling
rm -f "$RESULT_DIR/result.json" 2>/dev/null || sudo rm -f "$RESULT_DIR/result.json" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_DIR/result.json" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_DIR/result.json"
chmod 666 "$RESULT_DIR/result.json" 2>/dev/null || sudo chmod 666 "$RESULT_DIR/result.json" 2>/dev/null || true

# Also copy to /tmp for easier access
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

rm -f "$TEMP_JSON"

echo ""
echo "=== Export Complete ==="
echo "Results saved to: $RESULT_DIR"
ls -la "$RESULT_DIR"
echo ""
echo "Result JSON:"
cat "$RESULT_DIR/result.json"
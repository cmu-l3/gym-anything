#!/bin/bash
echo "=== Exporting Brain Tumor Segmentation Result ==="

source /workspace/scripts/task_utils.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
OUTPUT_SEG="$BRATS_DIR/agent_segmentation.nii.gz"
OUTPUT_REPORT="$BRATS_DIR/tumor_report.txt"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/brats_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Check if agent saved a segmentation file
AGENT_SEG_EXISTS="false"
AGENT_SEG_PATH=""

# Check multiple possible locations
POSSIBLE_SEG_PATHS=(
    "$OUTPUT_SEG"
    "$BRATS_DIR/agent_segmentation.nii"
    "$BRATS_DIR/Segmentation.nii.gz"
    "$BRATS_DIR/segmentation.nii.gz"
    "/home/ga/Documents/agent_segmentation.nii.gz"
    "/home/ga/agent_segmentation.nii.gz"
)

for path in "${POSSIBLE_SEG_PATHS[@]}"; do
    if [ -f "$path" ]; then
        AGENT_SEG_EXISTS="true"
        AGENT_SEG_PATH="$path"
        echo "Found agent segmentation at: $path"
        if [ "$path" != "$OUTPUT_SEG" ]; then
            cp "$path" "$OUTPUT_SEG" 2>/dev/null || true
        fi
        break
    fi
done

# Check if agent created a volume report
VOLUME_REPORT_EXISTS="false"
REPORTED_VOLUME_ML=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/report.txt"
    "$BRATS_DIR/volume.txt"
    "/home/ga/Documents/tumor_report.txt"
    "/home/ga/tumor_report.txt"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        VOLUME_REPORT_EXISTS="true"
        echo "Found volume report at: $path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        # Try to extract the volume value
        REPORTED_VOLUME_ML=$(grep -oE '[0-9]+\.?[0-9]*\s*(mL|ml|ML)' "$path" | head -1 | grep -oE '[0-9]+\.?[0-9]*' || echo "")
        if [ -z "$REPORTED_VOLUME_ML" ]; then
            # Try to find any number that might be the volume
            REPORTED_VOLUME_ML=$(grep -oE '[0-9]+\.?[0-9]*' "$path" | head -1 || echo "")
        fi
        echo "Reported volume: $REPORTED_VOLUME_ML mL"
        break
    fi
done

# Check for 3D visualization (screenshot analysis)
VISUALIZATION_CREATED="false"
# Check if there are any screenshots saved by the agent
AGENT_SCREENSHOTS=$(find "$BRATS_DIR" /home/ga/Documents -name "*.png" -newer /tmp/task_start_time 2>/dev/null | wc -l)
if [ "$AGENT_SCREENSHOTS" -gt 0 ]; then
    echo "Found $AGENT_SCREENSHOTS screenshots created during task"
    VISUALIZATION_CREATED="true"
fi

# Get segmentation file info
SEG_SIZE_BYTES=0
if [ -f "$OUTPUT_SEG" ]; then
    SEG_SIZE_BYTES=$(stat -c %s "$OUTPUT_SEG" 2>/dev/null || echo "0")
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Copy ground truth and agent segmentation for verification
echo "Preparing files for verification..."

cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" /tmp/ground_truth_seg.nii.gz 2>/dev/null || true
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_stats.json" /tmp/ground_truth_stats.json 2>/dev/null || true
chmod 644 /tmp/ground_truth_seg.nii.gz /tmp/ground_truth_stats.json 2>/dev/null || true

if [ -f "$OUTPUT_SEG" ]; then
    cp "$OUTPUT_SEG" /tmp/agent_segmentation.nii.gz 2>/dev/null || true
    chmod 644 /tmp/agent_segmentation.nii.gz 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_report.txt 2>/dev/null || true
    chmod 644 /tmp/agent_report.txt 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "agent_segmentation_exists": $AGENT_SEG_EXISTS,
    "agent_segmentation_path": "$AGENT_SEG_PATH",
    "agent_segmentation_size_bytes": $SEG_SIZE_BYTES,
    "volume_report_exists": $VOLUME_REPORT_EXISTS,
    "reported_volume_ml": "$REPORTED_VOLUME_ML",
    "visualization_created": $VISUALIZATION_CREATED,
    "agent_screenshots_count": $AGENT_SCREENSHOTS,
    "screenshot_exists": $([ -f "/tmp/brats_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/ground_truth_seg.nii.gz" ] && echo "true" || echo "false"),
    "sample_id": "$SAMPLE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/brats_task_result.json 2>/dev/null || sudo rm -f /tmp/brats_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/brats_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/brats_task_result.json
chmod 666 /tmp/brats_task_result.json 2>/dev/null || sudo chmod 666 /tmp/brats_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/brats_task_result.json
echo ""
echo "=== Export Complete ==="

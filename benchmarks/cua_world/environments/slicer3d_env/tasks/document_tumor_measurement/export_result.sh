#!/bin/bash
echo "=== Exporting Document Tumor Measurement Result ==="

source /workspace/scripts/task_utils.sh

# Get sample ID
if [ -f /tmp/task_sample_id.txt ]; then
    SAMPLE_ID=$(cat /tmp/task_sample_id.txt)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
OUTPUT_SCREENSHOT="$SCREENSHOT_DIR/tumor_measurement.png"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot of Slicer state
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Check for output screenshot
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE_KB=0
SCREENSHOT_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE_KB=$(du -k "$OUTPUT_SCREENSHOT" 2>/dev/null | cut -f1 || echo "0")
    
    # Check if created during task
    SCREENSHOT_MTIME=$(stat -c %Y "$OUTPUT_SCREENSHOT" 2>/dev/null || echo "0")
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
    
    # Copy to accessible location for verification
    cp "$OUTPUT_SCREENSHOT" /tmp/agent_screenshot.png 2>/dev/null || true
fi

# Also check for any new screenshots in the directory
NEW_SCREENSHOTS=""
for f in "$SCREENSHOT_DIR"/*.png; do
    if [ -f "$f" ]; then
        FMTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        if [ "$FMTIME" -gt "$TASK_START" ]; then
            NEW_SCREENSHOTS="$NEW_SCREENSHOTS $f"
        fi
    fi
done

# Try to export measurements from Slicer
echo "Attempting to export measurements from Slicer..."
MEASUREMENTS_JSON="/tmp/slicer_measurements.json"
rm -f "$MEASUREMENTS_JSON" 2>/dev/null || true

if [ "$SLICER_RUNNING" = "true" ]; then
    cat > /tmp/export_measurements.py << 'PYEOF'
import slicer
import json
import math
import os

output = {
    "line_markups": [],
    "text_markups": [],
    "volumes_loaded": 0,
    "measurement_value_mm": None
}

# Count loaded volumes
volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
output["volumes_loaded"] = len(volume_nodes)

# Get line markups (ruler measurements)
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a, b in zip(p1, p2)))
        
        output["line_markups"].append({
            "name": node.GetName(),
            "length_mm": round(length, 2),
            "p1": p1,
            "p2": p2
        })
        
        # Use first line measurement as the diameter
        if output["measurement_value_mm"] is None:
            output["measurement_value_mm"] = round(length, 2)

# Get text/fiducial markups (annotations)
fiducial_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
for node in fiducial_nodes:
    n_points = node.GetNumberOfControlPoints()
    for i in range(n_points):
        label = node.GetNthControlPointLabel(i)
        if label:
            output["text_markups"].append({
                "name": node.GetName(),
                "label": label,
                "point_index": i
            })

# Also check for dedicated text markups
text_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsTextNode")
for node in text_nodes:
    output["text_markups"].append({
        "name": node.GetName(),
        "text": node.GetText() if hasattr(node, 'GetText') else ""
    })

# Save to file
with open("/tmp/slicer_measurements.json", "w") as f:
    json.dump(output, f, indent=2)

print(f"Exported measurements: {len(output['line_markups'])} lines, {len(output['text_markups'])} texts")
PYEOF

    # Run the export script using Slicer Python
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_measurements.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    EXPORT_PID=$!
    
    # Wait with timeout
    for i in {1..15}; do
        if [ -f "$MEASUREMENTS_JSON" ]; then
            break
        fi
        sleep 1
    done
    
    kill $EXPORT_PID 2>/dev/null || true
fi

# Parse measurements if file exists
LINE_MARKUP_COUNT=0
TEXT_MARKUP_COUNT=0
EXTRACTED_DIAMETER=""
HAS_ANNOTATION="false"

if [ -f "$MEASUREMENTS_JSON" ]; then
    LINE_MARKUP_COUNT=$(python3 -c "import json; print(len(json.load(open('$MEASUREMENTS_JSON')).get('line_markups', [])))" 2>/dev/null || echo "0")
    TEXT_MARKUP_COUNT=$(python3 -c "import json; print(len(json.load(open('$MEASUREMENTS_JSON')).get('text_markups', [])))" 2>/dev/null || echo "0")
    EXTRACTED_DIAMETER=$(python3 -c "import json; v=json.load(open('$MEASUREMENTS_JSON')).get('measurement_value_mm'); print(v if v else '')" 2>/dev/null || echo "")
    
    if [ "$TEXT_MARKUP_COUNT" -gt 0 ]; then
        HAS_ANNOTATION="true"
    fi
fi

# Check for any markup files saved by user
MARKUP_FILES=$(find "$BRATS_DIR" "$SCREENSHOT_DIR" /home/ga -maxdepth 2 -name "*.mrk.json" -newer /tmp/task_start_time.txt 2>/dev/null | head -5)
SAVED_MARKUP_COUNT=$(echo "$MARKUP_FILES" | grep -c "mrk.json" || echo "0")

# Copy ground truth for verification
GT_FILE="$GROUND_TRUTH_DIR/${SAMPLE_ID}_diameter_gt.json"
if [ -f "$GT_FILE" ]; then
    cp "$GT_FILE" /tmp/diameter_ground_truth.json 2>/dev/null || true
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "sample_id": "$SAMPLE_ID",
    "slicer_was_running": $SLICER_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_kb": $SCREENSHOT_SIZE_KB,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "screenshot_path": "$OUTPUT_SCREENSHOT",
    "line_markup_count": $LINE_MARKUP_COUNT,
    "text_markup_count": $TEXT_MARKUP_COUNT,
    "has_annotation": $HAS_ANNOTATION,
    "extracted_diameter_mm": "$EXTRACTED_DIAMETER",
    "saved_markup_count": $SAVED_MARKUP_COUNT,
    "new_screenshots": "$NEW_SCREENSHOTS",
    "final_screenshot_path": "/tmp/task_final.png",
    "agent_screenshot_path": "/tmp/agent_screenshot.png"
}
EOF

# Move to final location
rm -f /tmp/tumor_measurement_result.json 2>/dev/null || sudo rm -f /tmp/tumor_measurement_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/tumor_measurement_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/tumor_measurement_result.json
chmod 666 /tmp/tumor_measurement_result.json 2>/dev/null || sudo chmod 666 /tmp/tumor_measurement_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/tumor_measurement_result.json"
cat /tmp/tumor_measurement_result.json
echo ""
echo "=== Export Complete ==="
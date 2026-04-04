#!/bin/bash
echo "=== Exporting Vertebral Compression Ratio Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Directories
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_REPORT="$EXPORTS_DIR/l1_compression_measurements.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || true

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
fi

# ============================================================
# Try to extract markup measurements from Slicer
# ============================================================
MARKUP_LINE_COUNT=0
EXTRACTED_MEASUREMENTS=""

if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Extracting measurements from Slicer scene..."
    
    cat > /tmp/extract_vcr_measurements.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/Exports"
os.makedirs(output_dir, exist_ok=True)

# Find line markup nodes
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line measurement node(s)")

measurements = []
for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        
        # Calculate length
        length = math.sqrt(sum((a-b)**2 for a, b in zip(p1, p2)))
        
        measurement = {
            "name": node.GetName(),
            "length_mm": round(length, 2),
            "p1": [round(x, 2) for x in p1],
            "p2": [round(x, 2) for x in p2],
            "z_avg": round((p1[2] + p2[2]) / 2, 2)
        }
        measurements.append(measurement)
        print(f"  {node.GetName()}: {length:.2f} mm")

# Save measurements
if measurements:
    meas_path = os.path.join(output_dir, "slicer_measurements.json")
    with open(meas_path, 'w') as f:
        json.dump({"line_measurements": measurements, "count": len(measurements)}, f, indent=2)
    print(f"Saved {len(measurements)} measurements to {meas_path}")

print(f"LINE_COUNT:{len(line_nodes)}")
PYEOF

    # Run extraction script
    EXTRACT_OUTPUT=$(su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --no-splash --no-main-window --python-script /tmp/extract_vcr_measurements.py 2>&1" || echo "")
    
    # Parse line count from output
    MARKUP_LINE_COUNT=$(echo "$EXTRACT_OUTPUT" | grep -o "LINE_COUNT:[0-9]*" | cut -d: -f2 || echo "0")
    if [ -z "$MARKUP_LINE_COUNT" ]; then
        MARKUP_LINE_COUNT=0
    fi
    
    echo "Markup line count: $MARKUP_LINE_COUNT"
fi

# ============================================================
# Check for output report file
# ============================================================
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_DATA="{}"

if [ -f "$OUTPUT_REPORT" ]; then
    REPORT_EXISTS="true"
    echo "Found report at: $OUTPUT_REPORT"
    
    # Check if created during task
    REPORT_MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
        echo "Report was created during task execution"
    fi
    
    # Read report data
    REPORT_DATA=$(cat "$OUTPUT_REPORT" 2>/dev/null || echo "{}")
fi

# ============================================================
# Extract values from report
# ============================================================
ANTERIOR_HEIGHT=""
POSTERIOR_HEIGHT=""
REPORTED_RATIO=""
REPORTED_CLASSIFICATION=""
ALL_FIELDS_PRESENT="false"

if [ "$REPORT_EXISTS" = "true" ]; then
    ANTERIOR_HEIGHT=$(python3 -c "import json; d=json.loads('$REPORT_DATA'); print(d.get('anterior_height_mm', ''))" 2>/dev/null || echo "")
    POSTERIOR_HEIGHT=$(python3 -c "import json; d=json.loads('$REPORT_DATA'); print(d.get('posterior_height_mm', ''))" 2>/dev/null || echo "")
    REPORTED_RATIO=$(python3 -c "import json; d=json.loads('$REPORT_DATA'); print(d.get('compression_ratio', ''))" 2>/dev/null || echo "")
    REPORTED_CLASSIFICATION=$(python3 -c "import json; d=json.loads('$REPORT_DATA'); print(d.get('classification', ''))" 2>/dev/null || echo "")
    
    # Check if all fields present
    if [ -n "$ANTERIOR_HEIGHT" ] && [ -n "$POSTERIOR_HEIGHT" ] && [ -n "$REPORTED_RATIO" ] && [ -n "$REPORTED_CLASSIFICATION" ]; then
        ALL_FIELDS_PRESENT="true"
    fi
    
    echo "Extracted values:"
    echo "  Anterior height: $ANTERIOR_HEIGHT mm"
    echo "  Posterior height: $POSTERIOR_HEIGHT mm"
    echo "  Compression ratio: $REPORTED_RATIO"
    echo "  Classification: $REPORTED_CLASSIFICATION"
fi

# ============================================================
# Also check for Slicer-saved measurements
# ============================================================
SLICER_MEASUREMENTS_FILE="$EXPORTS_DIR/slicer_measurements.json"
SLICER_MEAS_EXISTS="false"
SLICER_MEAS_DATA="{}"

if [ -f "$SLICER_MEASUREMENTS_FILE" ]; then
    SLICER_MEAS_EXISTS="true"
    SLICER_MEAS_DATA=$(cat "$SLICER_MEASUREMENTS_FILE" 2>/dev/null || echo "{}")
fi

# ============================================================
# Load ground truth
# ============================================================
GT_FILE="$GROUND_TRUTH_DIR/spine_measurements.json"
GT_DATA="{}"
if [ -f "$GT_FILE" ]; then
    GT_DATA=$(cat "$GT_FILE" 2>/dev/null || echo "{}")
fi

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/vcr_result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_sec": $((TASK_END - TASK_START)),
    "slicer_was_running": $SLICER_RUNNING,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "all_fields_present": $ALL_FIELDS_PRESENT,
    "markup_line_count": $MARKUP_LINE_COUNT,
    "reported_anterior_height_mm": "$ANTERIOR_HEIGHT",
    "reported_posterior_height_mm": "$POSTERIOR_HEIGHT",
    "reported_compression_ratio": "$REPORTED_RATIO",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "slicer_measurements_exists": $SLICER_MEAS_EXISTS,
    "slicer_measurements": $SLICER_MEAS_DATA,
    "ground_truth": $GT_DATA,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

# Move to final location
rm -f /tmp/vcr_task_result.json 2>/dev/null || sudo rm -f /tmp/vcr_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/vcr_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/vcr_task_result.json
chmod 666 /tmp/vcr_task_result.json 2>/dev/null || sudo chmod 666 /tmp/vcr_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Complete ==="
echo "Result saved to: /tmp/vcr_task_result.json"
cat /tmp/vcr_task_result.json
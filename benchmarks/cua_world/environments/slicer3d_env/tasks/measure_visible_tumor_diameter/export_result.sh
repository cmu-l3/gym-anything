#!/bin/bash
echo "=== Exporting Measure Visible Tumor Diameter Result ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
OUTPUT_FILE="/tmp/measure_tumor_result.json"
MEASUREMENT_FILE="$BRATS_DIR/tumor_diameter.mrk.json"

# Take final screenshot
take_screenshot /tmp/tumor_final.png ga

# Check if Slicer is running
SLICER_RUNNING=false
if is_slicer_running; then
    SLICER_RUNNING=true
fi

# Check if measurement file exists
MEASUREMENT_EXISTS=false
MEASURED_LENGTH=0
if [ -f "$MEASUREMENT_FILE" ]; then
    MEASUREMENT_EXISTS=true
    # Extract measurement from markup JSON
    MEASURED_LENGTH=$(python3 << PYEOF
import json
try:
    with open("$MEASUREMENT_FILE", 'r') as f:
        data = json.load(f)
    # Navigate the markup JSON structure to find length
    markups = data.get('markups', [])
    if markups:
        measurements = markups[0].get('measurements', [])
        for m in measurements:
            if m.get('name') == 'length':
                print(f"{m.get('value', 0):.2f}")
                break
        else:
            # Try controlPoints to calculate manually
            points = markups[0].get('controlPoints', [])
            if len(points) >= 2:
                import math
                p1 = points[0].get('position', [0,0,0])
                p2 = points[1].get('position', [0,0,0])
                dist = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
                print(f"{dist:.2f}")
            else:
                print("0")
    else:
        print("0")
except Exception as e:
    print("0")
PYEOF
)
fi

# Get ground truth diameter
GT_DIAMETER=45.0
if [ -f /tmp/tumor_ground_truth.txt ]; then
    GT_DIAMETER=$(cat /tmp/tumor_ground_truth.txt)
fi

# Check if any Line markup exists in Slicer
LINE_EXISTS=false
if $SLICER_RUNNING; then
    LINE_CHECK=$(sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-main-window --python-code "
import slicer
nodes = slicer.util.getNodesByClass('vtkMRMLMarkupsLineNode')
print('true' if nodes else 'false')
" 2>/dev/null | tail -1)
    if [ "$LINE_CHECK" = "true" ]; then
        LINE_EXISTS=true
    fi
fi

# Create result JSON
cat > "$OUTPUT_FILE" << EOF
{
    "slicer_running": $SLICER_RUNNING,
    "measurement_file_exists": $MEASUREMENT_EXISTS,
    "line_markup_exists": $LINE_EXISTS,
    "measured_length_mm": $MEASURED_LENGTH,
    "ground_truth_diameter_mm": $GT_DIAMETER,
    "screenshot_exists": $([ -f /tmp/tumor_final.png ] && echo "true" || echo "false")
}
EOF

echo "=== Export Complete ==="
echo "Result saved to: $OUTPUT_FILE"
cat "$OUTPUT_FILE"

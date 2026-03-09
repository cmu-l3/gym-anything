#!/bin/bash
echo "=== Exporting Measure Between Fiducials Result ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
OUTPUT_FILE="/tmp/measure_fiducials_result.json"
MEASUREMENT_FILE="$BRATS_DIR/distance_measurement.mrk.json"

take_screenshot /tmp/fiducial_measure_final.png ga

SLICER_RUNNING=false
if is_slicer_running; then
    SLICER_RUNNING=true
fi

# Check measurement file
MEASUREMENT_EXISTS=false
MEASURED_LENGTH=0
ENDPOINT_1="0,0,0"
ENDPOINT_2="0,0,0"
if [ -f "$MEASUREMENT_FILE" ]; then
    MEASUREMENT_EXISTS=true
    MEASUREMENT_DATA=$(python3 << PYEOF
import json
import math
try:
    with open("$MEASUREMENT_FILE", 'r') as f:
        data = json.load(f)
    markups = data.get('markups', [])
    if markups:
        # Get length
        measurements = markups[0].get('measurements', [])
        length = 0
        for m in measurements:
            if m.get('name') == 'length':
                length = m.get('value', 0)
                break

        # Get endpoints
        points = markups[0].get('controlPoints', [])
        if len(points) >= 2:
            p1 = points[0].get('position', [0,0,0])
            p2 = points[1].get('position', [0,0,0])
            if length == 0:
                length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
            print(f"{length:.2f}")
            print(f"{p1[0]:.2f},{p1[1]:.2f},{p1[2]:.2f}")
            print(f"{p2[0]:.2f},{p2[1]:.2f},{p2[2]:.2f}")
        else:
            print("0")
            print("0,0,0")
            print("0,0,0")
    else:
        print("0")
        print("0,0,0")
        print("0,0,0")
except Exception as e:
    print("0")
    print("0,0,0")
    print("0,0,0")
PYEOF
)
    MEASURED_LENGTH=$(echo "$MEASUREMENT_DATA" | head -1)
    ENDPOINT_1=$(echo "$MEASUREMENT_DATA" | head -2 | tail -1)
    ENDPOINT_2=$(echo "$MEASUREMENT_DATA" | tail -1)
fi

# Get ground truth
GT_DISTANCE=80.0
GT_POINT_A="0,0,0"
GT_POINT_B="0,0,0"
if [ -f /tmp/fiducial_distance_gt.txt ]; then
    GT_DISTANCE=$(head -1 /tmp/fiducial_distance_gt.txt)
    GT_POINT_A=$(head -2 /tmp/fiducial_distance_gt.txt | tail -1)
    GT_POINT_B=$(tail -1 /tmp/fiducial_distance_gt.txt)
fi

cat > "$OUTPUT_FILE" << EOF
{
    "slicer_running": $SLICER_RUNNING,
    "measurement_file_exists": $MEASUREMENT_EXISTS,
    "measured_length_mm": $MEASURED_LENGTH,
    "endpoint_1": "$ENDPOINT_1",
    "endpoint_2": "$ENDPOINT_2",
    "ground_truth_distance_mm": $GT_DISTANCE,
    "ground_truth_point_a": "$GT_POINT_A",
    "ground_truth_point_b": "$GT_POINT_B",
    "screenshot_exists": $([ -f /tmp/fiducial_measure_final.png ] && echo "true" || echo "false")
}
EOF

echo "=== Export Complete ==="
cat "$OUTPUT_FILE"

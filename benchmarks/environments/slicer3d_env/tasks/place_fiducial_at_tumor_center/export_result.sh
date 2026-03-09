#!/bin/bash
echo "=== Exporting Place Fiducial at Tumor Center Result ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
OUTPUT_FILE="/tmp/fiducial_tumor_result.json"
FIDUCIAL_FILE="$BRATS_DIR/tumor_center.mrk.json"

take_screenshot /tmp/fiducial_final.png ga

SLICER_RUNNING=false
if is_slicer_running; then
    SLICER_RUNNING=true
fi

# Check if fiducial file exists and extract position
FIDUCIAL_EXISTS=false
FIDUCIAL_POSITION="0,0,0"
if [ -f "$FIDUCIAL_FILE" ]; then
    FIDUCIAL_EXISTS=true
    FIDUCIAL_POSITION=$(python3 << PYEOF
import json
try:
    with open("$FIDUCIAL_FILE", 'r') as f:
        data = json.load(f)
    markups = data.get('markups', [])
    if markups:
        points = markups[0].get('controlPoints', [])
        if points:
            pos = points[0].get('position', [0,0,0])
            print(f"{pos[0]:.2f},{pos[1]:.2f},{pos[2]:.2f}")
        else:
            print("0,0,0")
    else:
        print("0,0,0")
except:
    print("0,0,0")
PYEOF
)
fi

# Check if any point fiducial exists in Slicer
POINT_EXISTS=false
if $SLICER_RUNNING; then
    POINT_CHECK=$(sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-main-window --python-code "
import slicer
nodes = slicer.util.getNodesByClass('vtkMRMLMarkupsFiducialNode')
print('true' if nodes else 'false')
" 2>/dev/null | tail -1)
    if [ "$POINT_CHECK" = "true" ]; then
        POINT_EXISTS=true
    fi
fi

# Get ground truth
GT_POSITION="0,0,0"
if [ -f /tmp/tumor_center_gt.txt ]; then
    GT_POSITION=$(cat /tmp/tumor_center_gt.txt)
fi

cat > "$OUTPUT_FILE" << EOF
{
    "slicer_running": $SLICER_RUNNING,
    "fiducial_file_exists": $FIDUCIAL_EXISTS,
    "point_markup_exists": $POINT_EXISTS,
    "fiducial_position": "$FIDUCIAL_POSITION",
    "ground_truth_position": "$GT_POSITION",
    "screenshot_exists": $([ -f /tmp/fiducial_final.png ] && echo "true" || echo "false")
}
EOF

echo "=== Export Complete ==="
cat "$OUTPUT_FILE"

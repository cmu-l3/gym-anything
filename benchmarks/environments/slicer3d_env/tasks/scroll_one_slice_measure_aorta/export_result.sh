#!/bin/bash
echo "=== Exporting Scroll and Measure Aorta Result ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_FILE="/tmp/scroll_aorta_result.json"
MEASUREMENT_FILE="$AMOS_DIR/aorta_diameter.mrk.json"

take_screenshot /tmp/scroll_aorta_final.png ga

SLICER_RUNNING=false
if is_slicer_running; then
    SLICER_RUNNING=true
fi

# Check measurement file
MEASUREMENT_EXISTS=false
MEASURED_LENGTH=0
if [ -f "$MEASUREMENT_FILE" ]; then
    MEASUREMENT_EXISTS=true
    MEASURED_LENGTH=$(python3 << PYEOF
import json
import math
try:
    with open("$MEASUREMENT_FILE", 'r') as f:
        data = json.load(f)
    markups = data.get('markups', [])
    if markups:
        measurements = markups[0].get('measurements', [])
        for m in measurements:
            if m.get('name') == 'length':
                print(f"{m.get('value', 0):.2f}")
                break
        else:
            points = markups[0].get('controlPoints', [])
            if len(points) >= 2:
                p1 = points[0].get('position', [0,0,0])
                p2 = points[1].get('position', [0,0,0])
                dist = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
                print(f"{dist:.2f}")
            else:
                print("0")
    else:
        print("0")
except:
    print("0")
PYEOF
)
fi

# Get current slice position to check if scrolled
CURRENT_SLICE=0
if $SLICER_RUNNING; then
    CURRENT_SLICE=$(sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-main-window --python-code "
import slicer
red_logic = slicer.app.layoutManager().sliceWidget('Red').sliceLogic()
print(f'{red_logic.GetSliceOffset():.2f}')
" 2>/dev/null | tail -1)
fi

# Get initial positions
INITIAL_SLICE=0
OPTIMAL_SLICE=0
if [ -f /tmp/scroll_aorta_positions.txt ]; then
    INITIAL_SLICE=$(grep "initial=" /tmp/scroll_aorta_positions.txt | cut -d= -f2)
    OPTIMAL_SLICE=$(grep "optimal=" /tmp/scroll_aorta_positions.txt | cut -d= -f2)
fi

cat > "$OUTPUT_FILE" << EOF
{
    "slicer_running": $SLICER_RUNNING,
    "measurement_file_exists": $MEASUREMENT_EXISTS,
    "measured_length_mm": $MEASURED_LENGTH,
    "initial_slice_position": $INITIAL_SLICE,
    "current_slice_position": ${CURRENT_SLICE:-0},
    "optimal_slice_position": $OPTIMAL_SLICE,
    "screenshot_exists": $([ -f /tmp/scroll_aorta_final.png ] && echo "true" || echo "false")
}
EOF

echo "=== Export Complete ==="
cat "$OUTPUT_FILE"

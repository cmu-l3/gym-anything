#!/bin/bash
echo "=== Exporting structural_gusset_plate result ==="

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
FCSTD_PATH="/home/ga/Documents/FreeCAD/gusset_plate.FCStd"
STEP_PATH="/home/ga/Documents/FreeCAD/gusset_plate.step"
STEP_PATH2="/home/ga/Documents/FreeCAD/gusset_plate.stp"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Check FCStd
FCSTD_EXISTS="false"
FCSTD_MTIME="0"
FCSTD_SIZE="0"
if [ -f "$FCSTD_PATH" ]; then
    FCSTD_EXISTS="true"
    FCSTD_MTIME=$(stat -c%Y "$FCSTD_PATH" 2>/dev/null || echo "0")
    FCSTD_SIZE=$(stat -c%s "$FCSTD_PATH" 2>/dev/null || echo "0")
fi

# Check STEP (.step or .stp)
STEP_EXISTS="false"
STEP_MTIME="0"
STEP_SIZE="0"
if [ -f "$STEP_PATH" ]; then
    STEP_EXISTS="true"
    STEP_MTIME=$(stat -c%Y "$STEP_PATH" 2>/dev/null || echo "0")
    STEP_SIZE=$(stat -c%s "$STEP_PATH" 2>/dev/null || echo "0")
elif [ -f "$STEP_PATH2" ]; then
    STEP_EXISTS="true"
    STEP_MTIME=$(stat -c%Y "$STEP_PATH2" 2>/dev/null || echo "0")
    STEP_SIZE=$(stat -c%s "$STEP_PATH2" 2>/dev/null || echo "0")
fi

python3 - << PYEOF
import json
result = {
    "task_start": int("$TASK_START"),
    "fcstd_exists": $FCSTD_EXISTS,
    "fcstd_mtime": int("$FCSTD_MTIME"),
    "fcstd_size": int("$FCSTD_SIZE"),
    "step_exists": $STEP_EXISTS,
    "step_mtime": int("$STEP_MTIME"),
    "step_size": int("$STEP_SIZE"),
    "export_timestamp": "$(date -Iseconds)"
}
with open("/tmp/structural_gusset_plate_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result JSON written to /tmp/structural_gusset_plate_result.json")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete: structural_gusset_plate ==="

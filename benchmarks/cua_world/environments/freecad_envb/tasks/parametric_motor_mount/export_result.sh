#!/bin/bash
echo "=== Exporting parametric_motor_mount result ==="

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
FCSTD_PATH="/home/ga/Documents/FreeCAD/motor_mount.FCStd"
STL_PATH="/home/ga/Documents/FreeCAD/motor_mount.stl"

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

# Check STL
STL_EXISTS="false"
STL_MTIME="0"
STL_SIZE="0"
if [ -f "$STL_PATH" ]; then
    STL_EXISTS="true"
    STL_MTIME=$(stat -c%Y "$STL_PATH" 2>/dev/null || echo "0")
    STL_SIZE=$(stat -c%s "$STL_PATH" 2>/dev/null || echo "0")
fi

python3 - << PYEOF
import json
result = {
    "task_start": int("$TASK_START"),
    "fcstd_exists": $FCSTD_EXISTS,
    "fcstd_mtime": int("$FCSTD_MTIME"),
    "fcstd_size": int("$FCSTD_SIZE"),
    "stl_exists": $STL_EXISTS,
    "stl_mtime": int("$STL_MTIME"),
    "stl_size": int("$STL_SIZE"),
    "export_timestamp": "$(date -Iseconds)"
}
with open("/tmp/parametric_motor_mount_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result JSON written to /tmp/parametric_motor_mount_result.json")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete: parametric_motor_mount ==="

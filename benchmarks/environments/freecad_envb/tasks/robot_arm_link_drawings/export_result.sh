#!/bin/bash
echo "=== Exporting robot_arm_link_drawings result ==="

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
FCSTD_PATH="/home/ga/Documents/FreeCAD/bracket_drawing.FCStd"
PDF_PATH="/home/ga/Documents/FreeCAD/bracket_drawing.pdf"

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

# Check PDF
PDF_EXISTS="false"
PDF_MTIME="0"
PDF_SIZE="0"
if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    PDF_MTIME=$(stat -c%Y "$PDF_PATH" 2>/dev/null || echo "0")
    PDF_SIZE=$(stat -c%s "$PDF_PATH" 2>/dev/null || echo "0")
fi

python3 - << PYEOF
import json
result = {
    "task_start": int("$TASK_START"),
    "fcstd_exists": $FCSTD_EXISTS,
    "fcstd_mtime": int("$FCSTD_MTIME"),
    "fcstd_size": int("$FCSTD_SIZE"),
    "pdf_exists": $PDF_EXISTS,
    "pdf_mtime": int("$PDF_MTIME"),
    "pdf_size": int("$PDF_SIZE"),
    "export_timestamp": "$(date -Iseconds)"
}
with open("/tmp/robot_arm_link_drawings_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result JSON written to /tmp/robot_arm_link_drawings_result.json")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete: robot_arm_link_drawings ==="

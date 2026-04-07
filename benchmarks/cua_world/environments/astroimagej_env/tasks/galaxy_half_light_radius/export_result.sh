#!/bin/bash
echo "=== Exporting Galaxy Half-Light Radius Result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Check if AstroImageJ is running
APP_RUNNING="false"
if is_aij_running; then
    APP_RUNNING="true"
fi

# Path to the expected report file
REPORT_FILE="/home/ga/AstroImages/measurements/half_light_radius.txt"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    REPORT_CONTENT=$(cat "$REPORT_FILE" 2>/dev/null | head -n 30)
fi

# Parse the report file securely using Python
python3 << PYEOF
import json
import re

report_content = """$REPORT_CONTENT"""
task_start = $TASK_START
task_end = $TASK_END
file_exists = "$FILE_EXISTS" == "true"
file_created_during_task = "$FILE_CREATED_DURING_TASK" == "true"
app_running = "$APP_RUNNING" == "true"

parsed_data = {
    "sky_background_mean": None,
    "center_x": None,
    "center_y": None,
    "total_flux_r120": None,
    "half_light_radius": None
}

if file_exists and report_content:
    try:
        # Extract values using regex to handle varying spacing/formatting
        bg_match = re.search(r"sky_background_mean:\s*([0-9.\-]+)", report_content, re.IGNORECASE)
        cx_match = re.search(r"center_x:\s*([0-9.\-]+)", report_content, re.IGNORECASE)
        cy_match = re.search(r"center_y:\s*([0-9.\-]+)", report_content, re.IGNORECASE)
        flux_match = re.search(r"total_flux_r120:\s*([0-9.\-]+)", report_content, re.IGNORECASE)
        hlr_match = re.search(r"half_light_radius:\s*([0-9.\-]+)", report_content, re.IGNORECASE)

        if bg_match: parsed_data["sky_background_mean"] = float(bg_match.group(1))
        if cx_match: parsed_data["center_x"] = float(cx_match.group(1))
        if cy_match: parsed_data["center_y"] = float(cy_match.group(1))
        if flux_match: parsed_data["total_flux_r120"] = float(flux_match.group(1))
        if hlr_match: parsed_data["half_light_radius"] = float(hlr_match.group(1))
    except Exception as e:
        print(f"Parse error: {e}")

result = {
    "task_start": task_start,
    "task_end": task_end,
    "app_was_running": app_running,
    "report_exists": file_exists,
    "file_created_during_task": file_created_during_task,
    "parsed_data": parsed_data,
    "raw_report_content": report_content
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json
echo "Exported result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="
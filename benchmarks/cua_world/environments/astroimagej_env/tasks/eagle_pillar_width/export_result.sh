#!/bin/bash
echo "=== Exporting Eagle Nebula Pillar task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time and start time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Detect AstroImageJ Windows
WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
AIJ_RUNNING="false"
PLOT_WINDOW_VISIBLE="false"

if echo "$WINDOWS_LIST" | grep -qi "astroimagej\|imagej"; then
    AIJ_RUNNING="true"
fi

if echo "$WINDOWS_LIST" | grep -qi "Plot\|Profile"; then
    PLOT_WINDOW_VISIBLE="true"
fi

# Process the results file
RESULTS_FILE="/home/ga/AstroImages/eagle_pillar/pillar_width_results.txt"

python3 << PYEOF
import json
import os
import re

results_path = "$RESULTS_FILE"
task_start = int("$TASK_START")

export_data = {
    "file_exists": False,
    "file_created_during_task": False,
    "raw_content": "",
    "width_pixels": None,
    "plate_scale": None,
    "width_arcsec": None,
    "y_coordinate": None,
    "aij_running": "$AIJ_RUNNING" == "true",
    "plot_window_visible": "$PLOT_WINDOW_VISIBLE" == "true"
}

if os.path.exists(results_path):
    export_data["file_exists"] = True
    mtime = os.path.getmtime(results_path)
    if mtime > task_start:
        export_data["file_created_during_task"] = True
        
    try:
        with open(results_path, "r") as f:
            content = f.read()
            export_data["raw_content"] = content
            
        # Parse numeric values robustly using regex
        match_pix = re.search(r'width_pixels:\s*([0-9]*\.?[0-9]+)', content, re.IGNORECASE)
        if match_pix: export_data["width_pixels"] = float(match_pix.group(1))
        
        match_scale = re.search(r'plate_scale:\s*([0-9]*\.?[0-9]+)', content, re.IGNORECASE)
        if match_scale: export_data["plate_scale"] = float(match_scale.group(1))
        
        match_arcsec = re.search(r'width_arcsec:\s*([0-9]*\.?[0-9]+)', content, re.IGNORECASE)
        if match_arcsec: export_data["width_arcsec"] = float(match_arcsec.group(1))
        
        match_y = re.search(r'y_coordinate:\s*([0-9]*\.?[0-9]+)', content, re.IGNORECASE)
        if match_y: export_data["y_coordinate"] = float(match_y.group(1))
            
    except Exception as e:
        export_data["parse_error"] = str(e)

# Save to temporary file then move safely
import tempfile
import shutil

fd, temp_path = tempfile.mkstemp(suffix='.json')
with os.fdopen(fd, 'w') as f:
    json.dump(export_data, f, indent=2)

os.system(f"chmod 666 {temp_path}")
os.system(f"cp {temp_path} /tmp/task_result.json")
os.remove(temp_path)
PYEOF

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
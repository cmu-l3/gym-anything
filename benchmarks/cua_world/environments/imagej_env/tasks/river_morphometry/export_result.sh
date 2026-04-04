#!/bin/bash
# Export script for river_morphometry task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting River Morphometry Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Use Python to parse the CSV robustly and check timestamps
python3 << 'PYEOF'
import json
import os
import re
import csv
import io

result_path = "/home/ga/ImageJ_Data/results/river_morphometry.csv"
timestamp_path = "/tmp/task_start_timestamp"
output_json = "/tmp/task_result.json"

result = {
    "file_exists": False,
    "file_created_during_task": False,
    "water_area": None,
    "widths": [],
    "sinuosity": None,
    "raw_content": "",
    "app_running": False
}

# 1. Check Application State
try:
    # Simple check if Fiji/ImageJ is in process list
    # In a real script we might use psutil, but here we use os.popen
    procs = os.popen("pgrep -f 'fiji\|ImageJ'").read()
    if procs.strip():
        result["app_running"] = True
except:
    pass

# 2. Check File Existence & Timestamp
try:
    start_time = 0
    if os.path.exists(timestamp_path):
        with open(timestamp_path, 'r') as f:
            start_time = int(f.read().strip())

    if os.path.exists(result_path):
        result["file_exists"] = True
        mtime = os.path.getmtime(result_path)
        if mtime > start_time:
            result["file_created_during_task"] = True
        
        # Read content
        try:
            with open(result_path, 'r', errors='replace') as f:
                content = f.read()
                result["raw_content"] = content
                
            # 3. Parse Content (Heuristic/Regex based on typical user output)
            content_lower = content.lower()
            
            # Search for Area
            # Look for lines like "Area, 12345" or "Water Area: 12345"
            area_matches = re.findall(r'(?:area|water|surface).*?[\s:,]+([\d\.]+)', content_lower)
            # Filter for reasonable values (pixel count for river is likely large)
            valid_areas = [float(x) for x in area_matches if float(x) > 1000]
            if valid_areas:
                result["water_area"] = valid_areas[0]
            
            # Search for Widths
            # Look for "Width" keyword or just generic numbers if labelled
            width_matches = re.findall(r'(?:width|cross|section|transect).*?[\s:,]+([\d\.]+)', content_lower)
            if not width_matches:
                # Fallback: if user put them in a list of numbers without clear labels
                # This is risky, but if we found area and sinuosity, remaining numbers might be widths
                pass
            
            result["widths"] = [float(x) for x in width_matches]
            
            # Search for Sinuosity
            sin_matches = re.findall(r'(?:sinuosity|index|ratio).*?[\s:,]+([\d\.]+)', content_lower)
            # Sinuosity is typically 1.0 - 3.0
            valid_sin = [float(x) for x in sin_matches if 1.0 <= float(x) <= 10.0]
            if valid_sin:
                result["sinuosity"] = valid_sin[0]
                
        except Exception as e:
            print(f"Error parsing file: {e}")

except Exception as e:
    print(f"Error in export script: {e}")

# Save JSON
with open(output_json, 'w') as f:
    json.dump(result, f, indent=2)

print("Export logic complete.")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
cat /tmp/task_result.json
echo "=== Export Complete ==="
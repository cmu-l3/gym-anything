#!/bin/bash
echo "=== Exporting sugar_activity_cloning task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_final.png" 2>/dev/null || true

# Use Python to safely parse the activity.info INI file and gather all artifacts
python3 << 'PYEOF'
import json
import os
import configparser

result = {
    "dir_exists": False,
    "info_exists": False,
    "svg_exists": False,
    "info_data": {},
    "report_lines": [],
    "report_exists": False,
    "original_bundle_id": "",
    "info_modified_during_task": False,
    "report_modified_during_task": False,
    "info_parse_error": None
}

try:
    with open("/tmp/original_bundle_id", "r") as f:
        result["original_bundle_id"] = f.read().strip()
except Exception:
    result["original_bundle_id"] = "org.laptop.Calculate"

try:
    with open("/tmp/task_start_ts", "r") as f:
        task_start = int(f.read().strip())
except Exception:
    task_start = 0

math_tools_dir = "/home/ga/Activities/MathTools.activity"
info_path = f"{math_tools_dir}/activity/activity.info"
svg_path = f"{math_tools_dir}/activity/math-tools.svg"
report_path = "/home/ga/Documents/activity_clone_report.txt"

if os.path.isdir(math_tools_dir):
    result["dir_exists"] = True

if os.path.isfile(info_path):
    result["info_exists"] = True
    result["info_modified_during_task"] = os.path.getmtime(info_path) >= task_start
    
    try:
        with open(info_path, 'r') as f:
            content = f.read()
        
        # INI files without headers break configparser. Sugar activity.info files
        # sometimes omit the [Activity] header or agents delete it.
        if '[Activity]' not in content and '[activity]' not in content.lower():
            content = '[Activity]\n' + content
            
        config = configparser.ConfigParser(strict=False)
        config.read_string(content)
        
        # Get the first section available
        sections = config.sections()
        if sections:
            # configparser stores keys in lowercase by default
            result["info_data"] = dict(config[sections[0]])
    except Exception as e:
        result["info_parse_error"] = str(e)

if os.path.isfile(svg_path):
    result["svg_exists"] = True

if os.path.isfile(report_path):
    result["report_exists"] = True
    result["report_modified_during_task"] = os.path.getmtime(report_path) >= task_start
    try:
        with open(report_path, 'r') as f:
            result["report_lines"] = [line.strip() for line in f.readlines() if line.strip()]
    except Exception as e:
        pass

# Write out the JSON result safely
try:
    with open("/tmp/sugar_activity_cloning_result.json", "w") as f:
        json.dump(result, f, indent=2)
except Exception as e:
    print(f"Failed to write result: {e}")
PYEOF

chmod 666 /tmp/sugar_activity_cloning_result.json
echo "Result saved to /tmp/sugar_activity_cloning_result.json"
cat /tmp/sugar_activity_cloning_result.json
echo "=== Export complete ==="
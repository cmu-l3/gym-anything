#!/bin/bash
echo "=== Exporting wildlife_exif_metadata_extraction task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Capture final state screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/exif_task_final.png" 2>/dev/null || true

# Parse the script and CSV outputs using a Python script
python3 << 'PYEOF' > /tmp/exif_task_result.json
import json
import os
import csv

result = {
    "script_exists": False,
    "script_size": 0,
    "csv_exists": False,
    "csv_size": 0,
    "header": [],
    "rows": [],
    "error": None
}

# 1. Check for the automation script
script_sh = "/home/ga/Documents/extract_exif.sh"
script_py = "/home/ga/Documents/extract_exif.py"

if os.path.exists(script_sh):
    result["script_exists"] = True
    result["script_size"] = os.path.getsize(script_sh)
elif os.path.exists(script_py):
    result["script_exists"] = True
    result["script_size"] = os.path.getsize(script_py)

# 2. Check for the generated CSV
csv_file = "/home/ga/Documents/photo_metadata.csv"

if os.path.exists(csv_file):
    result["csv_exists"] = True
    result["csv_size"] = os.path.getsize(csv_file)
    try:
        with open(csv_file, 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            lines = list(reader)
            if len(lines) > 0:
                result["header"] = lines[0]
            if len(lines) > 1:
                result["rows"] = lines[1:]
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/exif_task_result.json
echo "Result saved to /tmp/exif_task_result.json"
cat /tmp/exif_task_result.json
echo "=== Export complete ==="
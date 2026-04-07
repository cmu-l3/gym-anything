#!/bin/bash
# Export script for full_duplex_crossband_setup task

echo "=== Exporting full_duplex_crossband_setup result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority import -window root /tmp/task_final.png 2>/dev/null || true

# Check if application was running
APP_RUNNING=$(pgrep -x "gpredict" > /dev/null && echo "true" || echo "false")

# Safely extract GPredict internal configuration using Python to avoid Bash escaping issues
python3 << 'EOF'
import json
import os
import glob

result = {
    "task_start": int(os.environ.get("TASK_START", 0)),
    "task_end": int(os.environ.get("TASK_END", 0)),
    "app_was_running": os.environ.get("APP_RUNNING", "false") == "true",
    "radios": [],
    "rotators": [],
    "modules": []
}

conf_dir = "/home/ga/.config/Gpredict"

# Parse Radios
for rig_file in glob.glob(f"{conf_dir}/radios/*.rig"):
    try:
        with open(rig_file, 'r') as f:
            result["radios"].append({
                "filename": os.path.basename(rig_file),
                "mtime": os.path.getmtime(rig_file),
                "content": f.read()
            })
    except Exception:
        pass

# Parse Rotators
for rot_file in glob.glob(f"{conf_dir}/rotators/*.rot"):
    try:
        with open(rot_file, 'r') as f:
            result["rotators"].append({
                "filename": os.path.basename(rot_file),
                "mtime": os.path.getmtime(rot_file),
                "content": f.read()
            })
    except Exception:
        pass

# Parse Modules
for mod_file in glob.glob(f"{conf_dir}/modules/*.mod"):
    try:
        with open(mod_file, 'r') as f:
            result["modules"].append({
                "filename": os.path.basename(mod_file),
                "mtime": os.path.getmtime(mod_file),
                "content": f.read()
            })
    except Exception:
        pass

# Write to temp json safely
with open("/tmp/crossband_result_temp.json", "w") as f:
    json.dump(result, f)
EOF

# Move to final destination
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/crossband_result_temp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/crossband_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/crossband_result_temp.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="
#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# Export configuration data using Python to handle all files cleanly
python3 << 'EOF'
import os
import json
import time
import subprocess

# Check if gpredict is currently running
try:
    subprocess.check_output(["pgrep", "-f", "gpredict"])
    app_running = True
except subprocess.CalledProcessError:
    app_running = False

result = {
    "modules": [],
    "qths": [],
    "gpredict_cfg": "",
    "app_running": app_running,
    "export_timestamp": time.time()
}

conf_dir = "/home/ga/.config/Gpredict"
mod_dir = os.path.join(conf_dir, "modules")

# Grab all module configurations
if os.path.exists(mod_dir):
    for f in os.listdir(mod_dir):
        if f.endswith(".mod"):
            try:
                with open(os.path.join(mod_dir, f), "r") as file:
                    result["modules"].append({"filename": f, "content": file.read()})
            except: 
                pass

# Grab all ground station configurations
if os.path.exists(conf_dir):
    for f in os.listdir(conf_dir):
        if f.endswith(".qth"):
            try:
                with open(os.path.join(conf_dir, f), "r") as file:
                    result["qths"].append({"filename": f, "content": file.read()})
            except: 
                pass
            
# Grab main preference configuration
cfg_path = os.path.join(conf_dir, "gpredict.cfg")
if os.path.exists(cfg_path):
    try:
        with open(cfg_path, "r") as file:
            result["gpredict_cfg"] = file.read().replace('\n', '|')
    except: 
        pass

with open("/tmp/noaa_3screen_result.json", "w") as f:
    json.dump(result, f)
EOF

chmod 666 /tmp/noaa_3screen_result.json 2>/dev/null || true

echo "Result saved to /tmp/noaa_3screen_result.json"
echo "=== Export complete ==="
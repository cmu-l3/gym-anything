#!/bin/bash
echo "=== Exporting multisite_research_network result ==="

# 1. Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final_screenshot.png 2>/dev/null || true

# 2. Check if GPredict is currently running
GPREDICT_RUNNING="false"
if pgrep -x "gpredict" > /dev/null; then
    GPREDICT_RUNNING="true"
fi

# 3. Use Python to robustly parse all QTH and MOD files and package them into JSON
# This avoids complicated bash parsing of INI files and handles unexpected filenames
python3 << 'EOF'
import json
import os
import glob

result = {
    "gpredict_running": False,
    "task_start_timestamp": 0,
    "qth_files": {},
    "mod_files": {}
}

# Determine if GPredict was running based on bash env var passed in via python trick
if os.system('pgrep -x gpredict > /dev/null') == 0:
    result["gpredict_running"] = True

# Read task start time
try:
    with open("/tmp/task_start_timestamp", "r") as f:
        result["task_start_timestamp"] = float(f.read().strip())
except Exception:
    pass

conf_dir = "/home/ga/.config/Gpredict"

# Parse all ground station (.qth) files
qth_files = glob.glob(os.path.join(conf_dir, "*.qth"))
for qf in qth_files:
    name = os.path.basename(qf)
    try:
        mtime = os.path.getmtime(qf)
        with open(qf, "r", errors="replace") as f:
            content = f.read()
        result["qth_files"][name] = {
            "mtime": mtime,
            "content": content
        }
    except Exception as e:
        result["qth_files"][name] = {"error": str(e)}

# Parse all tracking module (.mod) files
mod_files = glob.glob(os.path.join(conf_dir, "modules", "*.mod"))
for mf in mod_files:
    name = os.path.basename(mf)
    try:
        mtime = os.path.getmtime(mf)
        with open(mf, "r", errors="replace") as f:
            content = f.read()
        result["mod_files"][name] = {
            "mtime": mtime,
            "content": content
        }
    except Exception as e:
        result["mod_files"][name] = {"error": str(e)}

# Save directly to final destination with open permissions
out_path = "/tmp/multisite_research_network_result.json"
with open(out_path, "w") as f:
    json.dump(result, f, indent=2)
os.chmod(out_path, 0o666)
EOF

echo "Result serialized to /tmp/multisite_research_network_result.json"
cat /tmp/multisite_research_network_result.json | head -n 30
echo "... (truncated for brevity)"
echo "=== Export Complete ==="
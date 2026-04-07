#!/bin/bash
echo "=== Exporting disaster_relief_imagery_tasking result ==="

# Capture timestamp evidence
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot BEFORE closing GPredict (critical for VLM verification)
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# Gracefully close GPredict to force it to flush configurations to disk
echo "Flushing configurations to disk..."
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -c "Gpredict" 2>/dev/null || pkill -x gpredict 2>/dev/null || true
sleep 3

# Paths to verify
MOD_PATH="/home/ga/.config/Gpredict/modules/Disaster_EO.mod"
CFG_PATH="/home/ga/.config/Gpredict/gpredict.cfg"
QTH_PATH="/home/ga/.config/Gpredict/Kathmandu.qth"

# Python script to safely capture file contents to JSON strings (avoiding bash grep issues)
python3 << EOF
import json
import os

def read_file(path):
    if os.path.exists(path):
        with open(path, 'r', encoding='utf-8', errors='ignore') as f:
            return f.read()
    return None

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "mod_content": read_file("$MOD_PATH"),
    "cfg_content": read_file("$CFG_PATH"),
    "qth_content": read_file("$QTH_PATH")
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
EOF

chmod 666 /tmp/task_result.json
echo "Result safely extracted to /tmp/task_result.json"
echo "=== Export complete ==="
#!/bin/bash
echo "=== Exporting Corporate Signage task results ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Copy the agent's proof screenshot to /tmp for easy verifier access
if [ -f /home/ga/Documents/signage_proof.png ]; then
    cp /home/ga/Documents/signage_proof.png /tmp/signage_proof.png 2>/dev/null || true
fi

# Take framework's own final screenshot for trajectory/record keeping
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to safely package the script contents and file existence checks into JSON
python3 -c '
import json
import os

res = {
    "script_exists": False,
    "script_executable": False,
    "script_contents": "",
    "screenshot_exists": False
}

script_path = "/home/ga/Desktop/launch_signage.sh"
if os.path.exists(script_path):
    res["script_exists"] = True
    res["script_executable"] = os.access(script_path, os.X_OK)
    with open(script_path, "r", errors="replace") as f:
        res["script_contents"] = f.read()

screenshot_path = "/home/ga/Documents/signage_proof.png"
if os.path.exists(screenshot_path):
    res["screenshot_exists"] = True

with open("/tmp/task_result.json", "w") as f:
    json.dump(res, f)
'

# Fix permissions so verifier can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
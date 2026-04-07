#!/bin/bash
echo "=== Exporting configure_exec_module_trigger result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check module statuses
EXEC_RUNNING="false"
if su - ga -c "seiscomp status exec" 2>/dev/null | grep -q "is running"; then
    EXEC_RUNNING="true"
fi

EXEC_ENABLED="false"
if su - ga -c "seiscomp list enabled" 2>/dev/null | grep -q "^exec$"; then
    EXEC_ENABLED="true"
fi

# Dump the effective configuration for the exec module
# This prevents parsing errors between scconfig's global vs user configs
su - ga -c "seiscomp exec scdumpcfg exec" > /tmp/exec_dump.cfg 2>/dev/null || true

# Use Python to safely construct the JSON output and handle base64 encoding
python3 << 'PYEOF'
import json
import os
import base64

result = {
    "script_exists": False,
    "script_executable": False,
    "script_content_b64": "",
    "exec_running": "$EXEC_RUNNING" == "true",
    "exec_enabled": "$EXEC_ENABLED" == "true",
    "dump_cfg": "",
    "task_start_time": 0
}

# Fetch task start time
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        result["task_start_time"] = int(f.read().strip())
except:
    pass

# Analyze target script
script_path = "/home/ga/scripts/log_origin.sh"
if os.path.exists(script_path):
    result["script_exists"] = True
    result["script_executable"] = os.access(script_path, os.X_OK)
    
    # Read file content safely
    try:
        with open(script_path, "rb") as f:
            result["script_content_b64"] = base64.b64encode(f.read()).decode('utf-8')
    except Exception as e:
        result["script_content_b64"] = ""

# Read the dumped SeisComP configuration
if os.path.exists("/tmp/exec_dump.cfg"):
    try:
        with open("/tmp/exec_dump.cfg", "r") as f:
            result["dump_cfg"] = f.read()
    except:
        pass

# Write result to exchange file
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="
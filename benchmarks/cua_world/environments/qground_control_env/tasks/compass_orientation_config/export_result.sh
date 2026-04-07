#!/bin/bash
set -e
echo "=== Exporting compass_orientation_config results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Query all 8 parameters via pymavlink
cat > /tmp/export_params.py << 'PYEOF'
import json, sys, time
sys.path.insert(0, "/opt/ardupilot")

result = {
    "parameters": {},
    "sitl_running": False,
    "qgc_running": False,
    "errors": []
}

# Check processes
import subprocess
try:
    result["sitl_running"] = subprocess.run(["pgrep", "-f", "arducopter"], capture_output=True).returncode == 0
    result["qgc_running"] = subprocess.run(["pgrep", "-f", "QGroundControl"], capture_output=True).returncode == 0
except Exception as e:
    result["errors"].append(f"Process check error: {str(e)}")

# Read task start time
try:
    with open("/tmp/task_start_time.txt") as f:
        result["task_start_time"] = float(f.read().strip())
except:
    result["task_start_time"] = 0

# Target parameters to query
target_params = [
    "AHRS_ORIENTATION",
    "COMPASS_ORIENT",
    "COMPASS_EXTERNAL",
    "COMPASS_USE2",
    "COMPASS_USE3",
    "COMPASS_LEARN",
    "COMPASS_OFS_X",
    "COMPASS_OFS_Y",
]

def read_param(master, sysid, compid, pname, timeout=5):
    """Robust param reader with retries."""
    for attempt in range(3):
        master.mav.param_request_read_send(sysid, compid, pname.encode('utf-8'), -1)
        deadline = time.time() + timeout
        while time.time() < deadline:
            pmsg = master.recv_match(type='PARAM_VALUE', blocking=True, timeout=1)
            if pmsg and pmsg.param_id.strip('\x00') == pname:
                return round(pmsg.param_value, 2)
        time.sleep(0.3)
    return None

try:
    from pymavlink import mavutil
    master = mavutil.mavlink_connection("tcp:127.0.0.1:5762", source_system=255, dialect='ardupilotmega')
    msg = master.recv_match(type='HEARTBEAT', blocking=True, timeout=15)
    
    if msg:
        sysid = msg.get_srcSystem()
        compid = msg.get_srcComponent()
        time.sleep(1)
        
        for param_name in target_params:
            val = read_param(master, sysid, compid, param_name)
            result["parameters"][param_name] = val
            if val is None:
                result["errors"].append(f"No response for {param_name}")
    else:
        result["errors"].append("No heartbeat from SITL")
        for param_name in target_params:
            result["parameters"][param_name] = None
            
    master.close()
except Exception as e:
    result["errors"].append(f"pymavlink error: {str(e)}")
    for param_name in target_params:
        if param_name not in result["parameters"]:
            result["parameters"][param_name] = None

# Write result to temp file, then move (to avoid permissions issues)
with open("/tmp/temp_task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

su - ga -c "python3 /tmp/export_params.py"

# Move the result to final location
cp /tmp/temp_task_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f /tmp/temp_task_result.json

cat /tmp/task_result.json
echo "=== Export complete ==="
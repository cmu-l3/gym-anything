#!/bin/bash
echo "=== Exporting LiDAR Payload Nav Tuning results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
QGC_RUNNING=$(pgrep -f "QGroundControl" > /dev/null && echo "true" || echo "false")

# Query all 7 parameters via pymavlink
python3 << PYEOF > /tmp/task_result.json
import json
import time
import sys

TARGET_PARAMS = [
    'WPNAV_SPEED', 'WPNAV_SPEED_UP', 'WPNAV_SPEED_DN',
    'WPNAV_ACCEL', 'WPNAV_RADIUS', 'LOIT_SPEED', 'RTL_SPEED'
]

def read_param(master, sysid, compid, pname, timeout=5):
    """Robust param read via mavlink."""
    for attempt in range(3):
        master.mav.param_request_read_send(sysid, compid, pname.encode('utf-8'), -1)
        deadline = time.time() + timeout
        while time.time() < deadline:
            pmsg = master.recv_match(type='PARAM_VALUE', blocking=True, timeout=1)
            if pmsg and pmsg.param_id.strip('\x00') == pname:
                return round(pmsg.param_value, 2)
        time.sleep(0.5)
    return None

result = {
    "task_start_time": $TASK_START,
    "qgc_running": $QGC_RUNNING,
    "parameters": {},
    "query_success": False,
    "error": None
}

try:
    from pymavlink import mavutil
    master = mavutil.mavlink_connection('tcp:127.0.0.1:5762', source_system=255, dialect='ardupilotmega')
    msg = master.recv_match(type='HEARTBEAT', blocking=True, timeout=15)
    
    if msg:
        sysid = msg.get_srcSystem()
        compid = msg.get_srcComponent()
        time.sleep(1)
        
        for pname in TARGET_PARAMS:
            result["parameters"][pname] = read_param(master, sysid, compid, pname)
            
        result["query_success"] = True
    else:
        result["error"] = "No heartbeat from SITL"

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
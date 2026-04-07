#!/bin/bash
echo "=== Exporting wildlife_silent_flight_tuning result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Query all 6 target parameters via pymavlink
python3 << 'PYEOF' > /tmp/task_result.json
import json, time, sys

TARGET_PARAMS = [
    'MOT_SPIN_MAX', 
    'ATC_ACCEL_P_MAX', 
    'ATC_ACCEL_R_MAX', 
    'ATC_ACCEL_Y_MAX', 
    'WPNAV_ACCEL', 
    'ANGLE_MAX'
]

def read_param(master, sysid, compid, pname, timeout=10):
    """Read a single param with robust filtering (handles QGC cross-talk)."""
    for attempt in range(3):
        master.mav.param_request_read_send(sysid, compid, pname.encode('utf-8'), -1)
        deadline = time.time() + timeout
        while time.time() < deadline:
            pmsg = master.recv_match(type='PARAM_VALUE', blocking=True, timeout=1)
            if pmsg and pmsg.param_id.strip('\x00') == pname:
                # We round to 3 decimals to avoid floating point representation issues on MOT_SPIN_MAX
                return round(pmsg.param_value, 3)
        time.sleep(0.3)
    return None

try:
    from pymavlink import mavutil
    master = mavutil.mavlink_connection('tcp:localhost:5762', source_system=255, dialect='ardupilotmega')
    msg = master.recv_match(type='HEARTBEAT', blocking=True, timeout=15)
    result = {}
    
    if msg:
        sysid = msg.get_srcSystem()
        compid = msg.get_srcComponent()
        time.sleep(2)
        for pname in TARGET_PARAMS:
            result[pname] = read_param(master, sysid, compid, pname)
        result['connected'] = True
    else:
        result = {p: None for p in TARGET_PARAMS}
        result['connected'] = False
        
    print(json.dumps(result))
    
except Exception as e:
    print(json.dumps({p: None for p in TARGET_PARAMS} | {'connected': False, 'error': str(e)}), file=sys.stderr)
    print(json.dumps({p: None for p in TARGET_PARAMS} | {'connected': False, 'error': str(e)}))
PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
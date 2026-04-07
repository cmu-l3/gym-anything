#!/bin/bash
echo "=== Exporting bridge_inspection_lidar_avoidance result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Query the 9 target parameters via pymavlink
python3 << 'PYEOF' > /tmp/task_result.json
import json, time, sys

TARGET_PARAMS = [
    'RNGFND1_TYPE', 'RNGFND1_ORIENT', 'RNGFND1_MAX_CM',
    'RNGFND2_TYPE', 'RNGFND2_ORIENT', 'RNGFND2_MAX_CM',
    'PRX1_TYPE', 'AVOID_ENABLE', 'AVOID_MARGIN'
]

def read_param(master, sysid, compid, pname, timeout=10):
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
    # Print error safely
    err_dict = {p: None for p in TARGET_PARAMS}
    err_dict['connected'] = False
    err_dict['error'] = str(e)
    print(json.dumps(err_dict))
PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
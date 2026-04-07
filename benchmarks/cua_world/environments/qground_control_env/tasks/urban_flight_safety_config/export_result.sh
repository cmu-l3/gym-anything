#!/bin/bash
echo "=== Exporting urban_flight_safety_config result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot as visual evidence of where the agent left off
take_screenshot /tmp/task_end_screenshot.png

# Query the 7 target parameters via pymavlink
python3 << 'PYEOF' > /tmp/task_result.json
import json
import time
import sys

TARGET_PARAMS = [
    'GPS_SATS_MIN', 'GPS_HDOP_GOOD',
    'COMPASS_USE', 'COMPASS_USE2', 'COMPASS_USE3',
    'EK3_SRC1_YAW', 'DISARM_DELAY'
]

def read_param(master, sysid, compid, pname, timeout=10):
    """Robust param fetcher with retries."""
    for attempt in range(3):
        master.mav.param_request_read_send(sysid, compid, pname.encode('utf-8'), -1)
        deadline = time.time() + timeout
        while time.time() < deadline:
            pmsg = master.recv_match(type='PARAM_VALUE', blocking=True, timeout=1)
            if pmsg and pmsg.param_id.strip('\x00') == pname:
                return round(pmsg.param_value, 2)
        time.sleep(0.5)
    return None

try:
    from pymavlink import mavutil
    master = mavutil.mavlink_connection('tcp:localhost:5762', source_system=255, dialect='ardupilotmega')
    
    # Wait for heartbeat to establish sysid/compid
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
    # Output to stderr so the logs capture it, while valid JSON goes to stdout
    print(json.dumps({p: None for p in TARGET_PARAMS} | {'connected': False, 'error': str(e)}), file=sys.stderr)
    print(json.dumps({p: None for p in TARGET_PARAMS} | {'connected': False, 'error': str(e)}))
PYEOF

echo "Result successfully extracted and saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="
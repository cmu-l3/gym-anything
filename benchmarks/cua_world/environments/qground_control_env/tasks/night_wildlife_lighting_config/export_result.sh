#!/bin/bash
echo "=== Exporting night_wildlife_lighting_config result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Query the 5 configured parameters via pymavlink
python3 << 'PYEOF' > /tmp/task_result.json
import json, time, sys

TARGET_PARAMS = [
    'RELAY_PIN', 'RC9_OPTION', 'WPNAV_SPEED', 'WPNAV_ACCEL', 'RTL_ALT'
]

def read_param(master, sysid, compid, pname, timeout=10):
    """Read a single param with robust filtering (handles QGC cross-talk)."""
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
    err_res = {p: None for p in TARGET_PARAMS}
    err_res['connected'] = False
    err_res['error'] = str(e)
    print(json.dumps(err_res), file=sys.stderr)
    print(json.dumps(err_res))
PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
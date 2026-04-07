#!/bin/bash
echo "=== Exporting autonomous_forest_obstacle_avoidance result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot as evidence
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Query all 8 parameters via pymavlink
python3 << 'PYEOF' > /tmp/params_out.json
import json, time, sys

TARGET_PARAMS = [
    'PRX1_TYPE', 
    'SERIAL2_PROTOCOL', 
    'SERIAL2_BAUD', 
    'OA_TYPE', 
    'OA_BR_LOOKAHEAD', 
    'OA_MARGIN_MAX', 
    'AVOID_ENABLE', 
    'WPNAV_SPEED'
]

def read_param(master, sysid, compid, pname, timeout=10):
    """Robust param reader with retries to handle dropped MAVLink packets."""
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
    print(json.dumps({p: None for p in TARGET_PARAMS} | {'connected': False, 'error': str(e)}), file=sys.stderr)
    print(json.dumps({p: None for p in TARGET_PARAMS} | {'connected': False, 'error': str(e)}))
PYEOF

PARAMS_JSON=$(cat /tmp/params_out.json 2>/dev/null || echo '{}')

cat > /tmp/task_result.json << JSONEOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "params": $PARAMS_JSON
}
JSONEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
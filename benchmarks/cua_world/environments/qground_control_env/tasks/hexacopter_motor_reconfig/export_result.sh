#!/bin/bash
echo "=== Exporting hexacopter_motor_reconfig result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Query all 8 target parameters via pymavlink
python3 << 'PYEOF' > /tmp/params_out.json
import json, time, sys

TARGET_PARAMS = [
    'FRAME_CLASS', 'MOT_SPIN_ARM', 'MOT_SPIN_MIN',
    'MOT_BAT_VOLT_MAX', 'MOT_BAT_VOLT_MIN', 'MOT_THST_EXPO',
    'MOT_THST_HOVER', 'BATT_CAPACITY'
]

def read_param(master, sysid, compid, pname, timeout=10):
    """Read a single param with robust filtering."""
    for attempt in range(3):
        master.mav.param_request_read_send(sysid, compid, pname.encode('utf-8'), -1)
        deadline = time.time() + timeout
        while time.time() < deadline:
            pmsg = master.recv_match(type='PARAM_VALUE', blocking=True, timeout=1)
            if pmsg and pmsg.param_id.strip('\x00') == pname:
                return round(pmsg.param_value, 4)
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
    err_result = {p: None for p in TARGET_PARAMS}
    err_result['connected'] = False
    err_result['error'] = str(e)
    print(json.dumps(err_result, file=sys.stderr))
    print(json.dumps(err_result))
PYEOF

PARAMS_JSON=$(cat /tmp/params_out.json 2>/dev/null || echo '{"connected": false}')

cat > /tmp/task_result.json << JSONEOF
{
    "task_start": $TASK_START,
    "params": $PARAMS_JSON
}
JSONEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
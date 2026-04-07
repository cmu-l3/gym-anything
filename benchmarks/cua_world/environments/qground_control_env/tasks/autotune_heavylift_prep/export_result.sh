#!/bin/bash
echo "=== Exporting autotune_heavylift_prep result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_end.png

# Query all 6 AutoTune/Filter parameters via pymavlink
python3 << 'PYEOF' > /tmp/params_out.json
import json, time, sys

TARGET_PARAMS = [
    'AUTOTUNE_AGGR', 
    'AUTOTUNE_AXES', 
    'RC7_OPTION',
    'ATC_RAT_RLL_FLTT', 
    'ATC_RAT_PIT_FLTT', 
    'INS_GYRO_FILTER'
]

def read_param(master, sysid, compid, pname, timeout=10):
    """Read a single param with robust filtering to handle MAVLink noise."""
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
        result['error'] = 'No heartbeat received'
    print(json.dumps(result))
except Exception as e:
    err_result = {p: None for p in TARGET_PARAMS}
    err_result['connected'] = False
    err_result['error'] = str(e)
    print(json.dumps(err_result), file=sys.stderr)
    print(json.dumps(err_result))
PYEOF

PARAMS_JSON=$(cat /tmp/params_out.json 2>/dev/null || echo '{"connected": false}')
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << JSONEOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "params": $PARAMS_JSON,
    "screenshot_path": "/tmp/task_end.png"
}
JSONEOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
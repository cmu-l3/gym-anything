#!/bin/bash
echo "=== Exporting swarm_drone_show_commissioning result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

PARAMS_FILE="/home/ga/Documents/QGC/vehicle42_show.params"
REPORT_FILE="/home/ga/Documents/QGC/signoff.txt"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Check Params File
PARAMS_FILE_EXISTS="false"
PARAMS_CONTENT='""'
if [ -f "$PARAMS_FILE" ]; then
    PARAMS_FILE_EXISTS="true"
    PARAMS_CONTENT=$(cat "$PARAMS_FILE" 2>/dev/null | python3 -c "
import sys, json
content = sys.stdin.read()
print(json.dumps(content))
" 2>/dev/null || echo '""')
fi

# Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT='""'
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" 2>/dev/null | python3 -c "
import sys, json
content = sys.stdin.read()
print(json.dumps(content))
" 2>/dev/null || echo '""')
fi

# Query live parameters via pymavlink
python3 << 'PYEOF' > /tmp/params_out.json
import json, time, sys
TARGET_PARAMS = [
    'SYSID_THISMAV', 'FS_THR_ENABLE', 'FS_GCS_ENABLE',
    'BATT_FS_LOW_ACT', 'FENCE_ACTION', 'FENCE_RADIUS',
    'FENCE_ALT_MAX', 'NTF_LED_TYPES'
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
    print(json.dumps({p: None for p in TARGET_PARAMS} | {'connected': False, 'error': str(e)}))
PYEOF

LIVE_PARAMS_JSON=$(cat /tmp/params_out.json 2>/dev/null || echo '{}')

cat > /tmp/task_result.json << JSONEOF
{
    "params_file_exists": $( [ "$PARAMS_FILE_EXISTS" = "true" ] && echo "true" || echo "false" ),
    "report_exists": $( [ "$REPORT_EXISTS" = "true" ] && echo "true" || echo "false" ),
    "params_content": $PARAMS_CONTENT,
    "report_content": $REPORT_CONTENT,
    "live_params": $LIVE_PARAMS_JSON
}
JSONEOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="
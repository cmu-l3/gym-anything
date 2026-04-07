#!/bin/bash
echo "=== Exporting heavy_lift_cinematic_tuning result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

PLAN_FILE="/home/ga/Documents/QGC/cinematic_test.plan"
REPORT_FILE="/home/ga/Documents/QGC/tuning_signoff.txt"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Read plan file details
PLAN_FOUND="false"
PLAN_SIZE=0
PLAN_MTIME=0
PLAN_CONTENT='""'

if [ -f "$PLAN_FILE" ]; then
    PLAN_FOUND="true"
    PLAN_SIZE=$(stat -c%s "$PLAN_FILE" 2>/dev/null || echo "0")
    PLAN_MTIME=$(stat -c%Y "$PLAN_FILE" 2>/dev/null || echo "0")
    PLAN_CONTENT=$(cat "$PLAN_FILE" 2>/dev/null | python3 -c "
import sys, json
content = sys.stdin.read()
print(json.dumps(content))
" 2>/dev/null || echo '""')
fi

# Read report file details
REPORT_FOUND="false"
REPORT_SIZE=0
REPORT_MTIME=0
REPORT_CONTENT='""'

if [ -f "$REPORT_FILE" ]; then
    REPORT_FOUND="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c%Y "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_CONTENT=$(cat "$REPORT_FILE" 2>/dev/null | python3 -c "
import sys, json
content = sys.stdin.read()
print(json.dumps(content))
" 2>/dev/null || echo '""')
fi

# Query parameters via pymavlink
python3 << 'PYEOF' > /tmp/params_out.json
import json, time
TARGET_PARAMS = [
    'WPNAV_SPEED', 'WPNAV_ACCEL', 'WPNAV_RADIUS',
    'WP_YAW_BEHAVIOR', 'ATC_ACCEL_Y_MAX', 'PILOT_Y_RATE'
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

PARAMS_JSON=$(cat /tmp/params_out.json 2>/dev/null || echo '{}')

cat > /tmp/task_result.json << JSONEOF
{
    "task_start": $TASK_START,
    "plan_found": $( [ "$PLAN_FOUND" = "true" ] && echo "true" || echo "false" ),
    "plan_size": $PLAN_SIZE,
    "plan_mtime": $PLAN_MTIME,
    "plan_content": $PLAN_CONTENT,
    "report_found": $( [ "$REPORT_FOUND" = "true" ] && echo "true" || echo "false" ),
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "report_content": $REPORT_CONTENT,
    "params": $PARAMS_JSON
}
JSONEOF

echo "Result saved to /tmp/task_result.json"
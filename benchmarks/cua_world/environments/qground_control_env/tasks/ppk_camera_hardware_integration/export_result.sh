#!/bin/bash
echo "=== Exporting ppk_camera_hardware_integration result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

REPORT_FILE="/home/ga/Documents/QGC/ppk_integration_report.txt"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

REPORT_FOUND="false"
REPORT_SIZE=0
REPORT_MTIME=0
REPORT_MODIFIED="false"
REPORT_CONTENT='""'

# 2. Check report file
if [ -f "$REPORT_FILE" ]; then
    REPORT_FOUND="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c%Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_MODIFIED="true"
    fi
    REPORT_CONTENT=$(cat "$REPORT_FILE" 2>/dev/null | python3 -c "
import sys, json
content = sys.stdin.read()
print(json.dumps(content))
" 2>/dev/null || echo '""')
fi

# 3. Query camera and servo parameters via pymavlink
python3 << 'PYEOF' > /tmp/params_out.json
import json, time
TARGET_PARAMS = [
    'CAM_TRIGG_TYPE', 'CAM_DURATION', 'CAM_MAX_ROLL',
    'SERVO9_FUNCTION', 'CAM_FEEDBACK_PIN', 'CAM_FEEDBACK_POL'
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

# 4. Write export JSON
cat > /tmp/task_result.json << JSONEOF
{
    "report_found": $( [ "$REPORT_FOUND" = "true" ] && echo "true" || echo "false" ),
    "report_path": "$REPORT_FILE",
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "task_start": $TASK_START,
    "report_modified": $( [ "$REPORT_MODIFIED" = "true" ] && echo "true" || echo "false" ),
    "report_content": $REPORT_CONTENT,
    "params": $PARAMS_JSON
}
JSONEOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="
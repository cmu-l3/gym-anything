#!/bin/bash
echo "=== Exporting telemetry_stream_config result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

REPORT_FILE="/home/ga/Documents/QGC/bandwidth_report.txt"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

REPORT_FOUND="false"
REPORT_SIZE=0
REPORT_MTIME=0
REPORT_MODIFIED="false"
REPORT_CONTENT='""'

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

# Query all 8 SR0_* parameters via pymavlink
python3 << 'PYEOF' > /tmp/params_out.json
import json, time, sys
TARGET_PARAMS = [
    'SR0_RAW_SENS', 'SR0_EXT_STAT', 'SR0_RC_CHAN', 'SR0_RAW_CTRL',
    'SR0_POSITION', 'SR0_EXTRA1', 'SR0_EXTRA2', 'SR0_EXTRA3'
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
    print(json.dumps({p: None for p in TARGET_PARAMS} | {'connected': False, 'error': str(e)}), file=sys.stderr)
    print(json.dumps({p: None for p in TARGET_PARAMS} | {'connected': False, 'error': str(e)}))
PYEOF

PARAMS_JSON=$(cat /tmp/params_out.json 2>/dev/null || echo '{}')

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
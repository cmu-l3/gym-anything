#!/bin/bash
echo "=== Exporting satcom_telemetry_bandwidth_reduction result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

EXPORT_FILE="/home/ga/Documents/QGC/satcom_link.params"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

FILE_FOUND="false"
FILE_SIZE=0
FILE_MTIME=0
FILE_MODIFIED="false"
FILE_CONTENT='""'

if [ -f "$EXPORT_FILE" ]; then
    FILE_FOUND="true"
    FILE_SIZE=$(stat -c%s "$EXPORT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$EXPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    # Escape file content for JSON embedding
    FILE_CONTENT=$(cat "$EXPORT_FILE" 2>/dev/null | python3 -c "
import sys, json
content = sys.stdin.read()
print(json.dumps(content))
" 2>/dev/null || echo '""')
fi

# Query all 8 live safety parameters via pymavlink
echo "--- Querying live parameters ---"
python3 << 'PYEOF' > /tmp/params_out.json
import json, time, sys

TARGET_PARAMS = [
    'SR2_POSITION', 'SR2_EXT_STAT', 'SR2_EXTRA1', 'SR2_EXTRA2',
    'SR2_EXTRA3', 'SR2_RAW_CTRL', 'SR2_RAW_SENS', 'SR2_RC_CHAN'
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
    "file_found": $( [ "$FILE_FOUND" = "true" ] && echo "true" || echo "false" ),
    "file_path": "$EXPORT_FILE",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "task_start": $TASK_START,
    "file_modified": $( [ "$FILE_MODIFIED" = "true" ] && echo "true" || echo "false" ),
    "file_content": $FILE_CONTENT,
    "live_params": $PARAMS_JSON
}
JSONEOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="
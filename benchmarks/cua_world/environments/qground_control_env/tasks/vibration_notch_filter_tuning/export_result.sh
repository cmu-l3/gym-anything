#!/bin/bash
echo "=== Exporting vibration_notch_filter_tuning result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

SUMMARY_FILE="/home/ga/Documents/QGC/filter_summary.txt"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

FILE_FOUND="false"
FILE_SIZE=0
FILE_MTIME=0
FILE_MODIFIED="false"
FILE_CONTENT='""'

if [ -f "$SUMMARY_FILE" ]; then
    FILE_FOUND="true"
    FILE_SIZE=$(stat -c%s "$SUMMARY_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$SUMMARY_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    FILE_CONTENT=$(cat "$SUMMARY_FILE" 2>/dev/null | python3 -c "
import sys, json
content = sys.stdin.read()
print(json.dumps(content))
" 2>/dev/null || echo '""')
fi

# Query the 7 INS_HNTCH parameters via pymavlink
python3 << 'PYEOF' > /tmp/params_out.json
import json, time, sys
TARGET_PARAMS = [
    'INS_HNTCH_ENABLE', 'INS_HNTCH_MODE', 'INS_HNTCH_FREQ',
    'INS_HNTCH_BW', 'INS_HNTCH_REF', 'INS_HNTCH_ATT', 'INS_LOG_BAT_OPT'
]

def read_param(master, sysid, compid, pname, timeout=10):
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
    print(json.dumps({p: None for p in TARGET_PARAMS} | {'connected': False, 'error': str(e)}), file=sys.stderr)
    print(json.dumps({p: None for p in TARGET_PARAMS} | {'connected': False, 'error': str(e)}))
PYEOF

PARAMS_JSON=$(cat /tmp/params_out.json 2>/dev/null || echo '{}')

cat > /tmp/task_result.json << JSONEOF
{
    "summary_found": $( [ "$FILE_FOUND" = "true" ] && echo "true" || echo "false" ),
    "summary_path": "$SUMMARY_FILE",
    "summary_size": $FILE_SIZE,
    "summary_mtime": $FILE_MTIME,
    "task_start": $TASK_START,
    "summary_modified": $( [ "$FILE_MODIFIED" = "true" ] && echo "true" || echo "false" ),
    "summary_content": $FILE_CONTENT,
    "params": $PARAMS_JSON
}
JSONEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
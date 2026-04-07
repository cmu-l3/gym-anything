#!/bin/bash
echo "=== Exporting volcanic_crater_thermal_overwatch result ==="

source /workspace/scripts/task_utils.sh

# 1. Final screenshot
take_screenshot /tmp/task_end.png

# 2. Check File Information
PLAN_FILE="/home/ga/Documents/QGC/crater_monitor.plan"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

FILE_FOUND="false"
FILE_SIZE=0
FILE_MTIME=0
MODIFIED_DURING_TASK="false"
PLAN_CONTENT='""'

if [ -f "$PLAN_FILE" ]; then
    FILE_FOUND="true"
    FILE_SIZE=$(stat -c%s "$PLAN_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$PLAN_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        MODIFIED_DURING_TASK="true"
    fi
    # Safely escape plan JSON for embedding
    PLAN_CONTENT=$(cat "$PLAN_FILE" 2>/dev/null | python3 -c "
import sys, json
content = sys.stdin.read()
print(json.dumps(content))
" 2>/dev/null || echo '""')
fi

# 3. Read QGroundControl Settings for RTSP config
RTSP_URL=$(grep -i "rtspUrl=" /home/ga/.config/QGroundControl/QGroundControl.ini | head -1 | cut -d'=' -f2-)
if [ -z "$RTSP_URL" ]; then
    RTSP_URL=""
fi
# Escape for JSON embedding
RTSP_URL_JSON=$(python3 -c "import json; print(json.dumps('''$RTSP_URL'''))")


# 4. Query RTL_ALT parameter via pymavlink
python3 << 'PYEOF' > /tmp/params_out.json
import json, time
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
        result['RTL_ALT'] = read_param(master, sysid, compid, 'RTL_ALT')
        result['connected'] = True
    else:
        result = {'RTL_ALT': None, 'connected': False}
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'RTL_ALT': None, 'connected': False, 'error': str(e)}))
PYEOF

PARAMS_JSON=$(cat /tmp/params_out.json 2>/dev/null || echo '{"RTL_ALT": null, "connected": false}')

# 5. Create combined result JSON
cat > /tmp/task_result.json << JSONEOF
{
    "file_found": $( [ "$FILE_FOUND" = "true" ] && echo "true" || echo "false" ),
    "file_path": "$PLAN_FILE",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "task_start": $TASK_START,
    "modified_during_task": $( [ "$MODIFIED_DURING_TASK" = "true" ] && echo "true" || echo "false" ),
    "rtsp_url": $RTSP_URL_JSON,
    "params": $PARAMS_JSON,
    "plan_content": $PLAN_CONTENT
}
JSONEOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="
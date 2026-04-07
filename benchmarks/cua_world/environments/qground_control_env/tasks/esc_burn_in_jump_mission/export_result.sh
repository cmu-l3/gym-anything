#!/bin/bash
echo "=== Exporting esc_burn_in_jump_mission result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

PLAN_FILE="/home/ga/Documents/QGC/burn_in.plan"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

FILE_FOUND="false"
FILE_SIZE=0
FILE_MTIME=0
MODIFIED_DURING_TASK="false"
PLAN_CONTENT='""'

# Check if the plan file was successfully created
if [ -f "$PLAN_FILE" ]; then
    FILE_FOUND="true"
    FILE_SIZE=$(stat -c%s "$PLAN_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$PLAN_FILE" 2>/dev/null || echo "0")
    
    # Verify file was created/modified during the active task window
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        MODIFIED_DURING_TASK="true"
    fi
    
    # Read and JSON-escape the plan content so it can be nested in the result payload
    PLAN_CONTENT=$(cat "$PLAN_FILE" 2>/dev/null | python3 -c "
import sys, json
content = sys.stdin.read()
print(json.dumps(content))
" 2>/dev/null || echo '""')
fi

# Query the live WPNAV_SPEED parameter via pymavlink
python3 << 'PYEOF' > /tmp/params_out.json
import json, time, sys
TARGET_PARAM = 'WPNAV_SPEED'

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
        result[TARGET_PARAM] = read_param(master, sysid, compid, TARGET_PARAM)
        result['connected'] = True
    else:
        result[TARGET_PARAM] = None
        result['connected'] = False
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({TARGET_PARAM: None, 'connected': False, 'error': str(e)}))
PYEOF

PARAMS_JSON=$(cat /tmp/params_out.json 2>/dev/null || echo '{"WPNAV_SPEED": null}')

# Create the final result JSON payload
cat > /tmp/task_result.json << JSONEOF
{
    "file_found": $( [ "$FILE_FOUND" = "true" ] && echo "true" || echo "false" ),
    "file_path": "$PLAN_FILE",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "task_start": $TASK_START,
    "modified_during_task": $( [ "$MODIFIED_DURING_TASK" = "true" ] && echo "true" || echo "false" ),
    "plan_content": $PLAN_CONTENT,
    "params": $PARAMS_JSON
}
JSONEOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="
#!/bin/bash
echo "=== Exporting custom_payload_hardware_integration result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

LOG_FILE="/home/ga/Documents/QGC/integration_log.txt"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

LOG_FOUND="false"
LOG_MODIFIED="false"
LOG_CONTENT='""'

# Check log file status and read content
if [ -f "$LOG_FILE" ]; then
    LOG_FOUND="true"
    LOG_MTIME=$(stat -c%Y "$LOG_FILE" 2>/dev/null || echo "0")
    if [ "$LOG_MTIME" -ge "$TASK_START" ]; then
        LOG_MODIFIED="true"
    fi
    # Safely read and JSON-escape the file content
    LOG_CONTENT=$(cat "$LOG_FILE" 2>/dev/null | python3 -c "
import sys, json
print(json.dumps(sys.stdin.read()))
" 2>/dev/null || echo '""')
fi

# Query ArduPilot parameters via pymavlink
python3 << 'PYEOF' > /tmp/params_out.json
import json, time, sys
TARGET_PARAMS = [
    'MNT1_TYPE', 'CAM1_TYPE',
    'SERVO9_FUNCTION', 'SERVO10_FUNCTION', 'SERVO11_FUNCTION',
    'MNT1_PITCH_MIN', 'MNT1_PITCH_MAX', 'CAM1_DURATION'
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

# Generate final results JSON
cat > /tmp/task_result.json << JSONEOF
{
    "log_found": $( [ "$LOG_FOUND" = "true" ] && echo "true" || echo "false" ),
    "log_modified": $( [ "$LOG_MODIFIED" = "true" ] && echo "true" || echo "false" ),
    "log_content": $LOG_CONTENT,
    "params": $PARAMS_JSON,
    "task_start": $TASK_START
}
JSONEOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="
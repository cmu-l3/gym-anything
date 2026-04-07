#!/bin/bash
echo "=== Exporting flight_school_trainer_detuning result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end.png

PROFILE_FILE="/home/ga/Documents/QGC/novice_profile.params"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

FILE_FOUND="false"
FILE_SIZE=0
FILE_MTIME=0
FILE_MODIFIED="false"
HAS_HEADER="false"
EXPORTED_PARAMS=""

if [ -f "$PROFILE_FILE" ]; then
    FILE_FOUND="true"
    FILE_SIZE=$(stat -c%s "$PROFILE_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$PROFILE_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    if grep -qi "Onboard parameters" "$PROFILE_FILE"; then
        HAS_HEADER="true"
    fi
    
    # Extract just the lines for our 6 specific parameters to avoid embedding thousands of lines
    EXPORTED_PARAMS=$(grep -E "(ANGLE_MAX|PILOT_SPEED_UP|PILOT_SPEED_DN|LOIT_SPEED|LOIT_ACC_MAX|PILOT_Y_RATE)" "$PROFILE_FILE" 2>/dev/null)
fi

# Query pymavlink for live parameters
python3 << 'PYEOF' > /tmp/params_out.json
import json, time
TARGET_PARAMS = ['ANGLE_MAX', 'PILOT_SPEED_UP', 'PILOT_SPEED_DN', 'LOIT_SPEED', 'LOIT_ACC_MAX', 'PILOT_Y_RATE']

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

# Safely encode exported params as JSON string
EXPORTED_PARAMS_JSON=$(python3 -c "import json, sys; print(json.dumps(sys.stdin.read()))" <<< "$EXPORTED_PARAMS")

cat > /tmp/task_result.json << JSONEOF
{
    "file_found": $FILE_FOUND,
    "file_path": "$PROFILE_FILE",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "task_start": $TASK_START,
    "file_modified": $FILE_MODIFIED,
    "has_header": $HAS_HEADER,
    "exported_params": $EXPORTED_PARAMS_JSON,
    "live_params": $LIVE_PARAMS_JSON
}
JSONEOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="
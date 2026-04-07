#!/bin/bash
echo "=== Exporting adsb_traffic_avoidance_config result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

PARAMS_FILE="/home/ga/Documents/QGC/adsb_configured.params"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

FILE_FOUND="false"
FILE_SIZE=0
FILE_MTIME=0
FILE_MODIFIED="false"
FILE_CONTAINS_AVD="false"

if [ -f "$PARAMS_FILE" ]; then
    FILE_FOUND="true"
    FILE_SIZE=$(stat -c%s "$PARAMS_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$PARAMS_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Check if the exported parameters file contains the requested parameters
    if grep -q "AVD_ENABLE" "$PARAMS_FILE" 2>/dev/null; then
        FILE_CONTAINS_AVD="true"
    fi
fi

# Query live parameters via pymavlink
python3 << 'PYEOF' > /tmp/params_out.json
import json, time, sys
TARGET_PARAMS = [
    'ADSB_ENABLE', 'AVD_ENABLE', 'AVD_W_DIST_XY', 
    'AVD_W_DIST_Z', 'AVD_F_DIST_XY', 'AVD_F_DIST_Z', 'AVD_F_ACTION'
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

# Combine file status and pymavlink results into the final task_result.json
cat > /tmp/task_result.json << JSONEOF
{
    "file_found": $( [ "$FILE_FOUND" = "true" ] && echo "true" || echo "false" ),
    "file_path": "$PARAMS_FILE",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "task_start": $TASK_START,
    "file_modified": $( [ "$FILE_MODIFIED" = "true" ] && echo "true" || echo "false" ),
    "file_contains_avd": $( [ "$FILE_CONTAINS_AVD" = "true" ] && echo "true" || echo "false" ),
    "live_params": $PARAMS_JSON
}
JSONEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
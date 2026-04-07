#!/bin/bash
echo "=== Exporting sar_thermal_survey_preparation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# ---------- 1. Check mission plan file ----------
PLAN_FILE="/home/ga/Documents/QGC/sar_thermal_survey.plan"
PLAN_FOUND="false"
PLAN_SIZE=0
PLAN_MTIME=0
PLAN_MODIFIED="false"
PLAN_CONTENT='""'

if [ -f "$PLAN_FILE" ]; then
    PLAN_FOUND="true"
    PLAN_SIZE=$(stat -c%s "$PLAN_FILE" 2>/dev/null || echo "0")
    PLAN_MTIME=$(stat -c%Y "$PLAN_FILE" 2>/dev/null || echo "0")
    if [ "$PLAN_MTIME" -ge "$TASK_START" ]; then
        PLAN_MODIFIED="true"
    fi
    PLAN_CONTENT=$(cat "$PLAN_FILE" 2>/dev/null | python3 -c "
import sys, json
content = sys.stdin.read()
print(json.dumps(content))
" 2>/dev/null || echo '""')
fi

# ---------- 2. Check parameter export file ----------
PARAMS_EXPORT="/home/ga/Documents/QGC/sar_safety_params.params"
PARAMS_EXPORT_FOUND="false"
PARAMS_EXPORT_MTIME=0
PARAMS_EXPORT_MODIFIED="false"

if [ -f "$PARAMS_EXPORT" ]; then
    PARAMS_EXPORT_FOUND="true"
    PARAMS_EXPORT_MTIME=$(stat -c%Y "$PARAMS_EXPORT" 2>/dev/null || echo "0")
    if [ "$PARAMS_EXPORT_MTIME" -ge "$TASK_START" ]; then
        PARAMS_EXPORT_MODIFIED="true"
    fi
fi

# ---------- 3. Check mission brief file ----------
BRIEF_FILE="/home/ga/Documents/QGC/sar_mission_brief.txt"
BRIEF_FOUND="false"
BRIEF_SIZE=0
BRIEF_MTIME=0
BRIEF_MODIFIED="false"
BRIEF_CONTENT='""'

if [ -f "$BRIEF_FILE" ]; then
    BRIEF_FOUND="true"
    BRIEF_SIZE=$(stat -c%s "$BRIEF_FILE" 2>/dev/null || echo "0")
    BRIEF_MTIME=$(stat -c%Y "$BRIEF_FILE" 2>/dev/null || echo "0")
    if [ "$BRIEF_MTIME" -ge "$TASK_START" ]; then
        BRIEF_MODIFIED="true"
    fi
    BRIEF_CONTENT=$(cat "$BRIEF_FILE" 2>/dev/null | python3 -c "
import sys, json
content = sys.stdin.read()
print(json.dumps(content))
" 2>/dev/null || echo '""')
fi

# ---------- 4. Query ArduPilot parameters via pymavlink ----------
python3 << 'PYEOF' > /tmp/params_out.json
import json, time
TARGET_PARAMS = ['FENCE_ENABLE', 'FENCE_ACTION', 'FS_GCS_ENABLE', 'RTL_ALT_M', 'WP_SPD']

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
    master = mavutil.mavlink_connection('tcp:localhost:5762',
                                        source_system=255,
                                        dialect='ardupilotmega')
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

# ---------- 5. Read QGC settings for RTSP config ----------
python3 << 'PYEOF' > /tmp/ini_data.json
import json, re, os

ini_path = '/home/ga/.config/QGroundControl/QGroundControl.ini'
result = {
    'VideoSource': '',
    'rtspUrl': ''
}

if os.path.exists(ini_path):
    try:
        with open(ini_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()

            m = re.search(r'^VideoSource=(.*)$', content, re.MULTILINE)
            if m: result['VideoSource'] = m.group(1).strip()

            m = re.search(r'^rtspUrl=(.*)$', content, re.MULTILINE)
            if m: result['rtspUrl'] = m.group(1).strip()

    except Exception as e:
        result['error'] = str(e)

print(json.dumps(result))
PYEOF

INI_DATA=$(cat /tmp/ini_data.json 2>/dev/null || echo '{}')

# ---------- 6. Write consolidated result ----------
cat > /tmp/task_result.json << JSONEOF
{
    "plan_found": $( [ "$PLAN_FOUND" = "true" ] && echo "true" || echo "false" ),
    "plan_path": "$PLAN_FILE",
    "plan_size": $PLAN_SIZE,
    "plan_mtime": $PLAN_MTIME,
    "plan_modified": $( [ "$PLAN_MODIFIED" = "true" ] && echo "true" || echo "false" ),
    "plan_content": $PLAN_CONTENT,
    "params_export_found": $( [ "$PARAMS_EXPORT_FOUND" = "true" ] && echo "true" || echo "false" ),
    "params_export_modified": $( [ "$PARAMS_EXPORT_MODIFIED" = "true" ] && echo "true" || echo "false" ),
    "brief_found": $( [ "$BRIEF_FOUND" = "true" ] && echo "true" || echo "false" ),
    "brief_size": $BRIEF_SIZE,
    "brief_modified": $( [ "$BRIEF_MODIFIED" = "true" ] && echo "true" || echo "false" ),
    "brief_content": $BRIEF_CONTENT,
    "task_start": $TASK_START,
    "params": $PARAMS_JSON,
    "qgc_settings": $INI_DATA
}
JSONEOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="

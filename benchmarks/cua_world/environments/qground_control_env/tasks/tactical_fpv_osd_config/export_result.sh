#!/bin/bash
echo "=== Exporting tactical_fpv_osd_config result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot as evidence
take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Query the 16 target parameters via pymavlink
python3 << 'PYEOF' > /tmp/params_out.json
import json, time, sys
TARGET_PARAMS = [
    'OSD_TYPE', 'OSD1_ENABLE',
    'OSD1_FLTMODE_EN', 'OSD1_FLTMODE_X', 'OSD1_FLTMODE_Y',
    'OSD1_BAT_VOLT_EN', 'OSD1_BAT_VOLT_X', 'OSD1_BAT_VOLT_Y',
    'OSD1_CURRENT_EN', 'OSD1_CURRENT_X', 'OSD1_CURRENT_Y',
    'OSD1_RSSI_EN', 'OSD1_RSSI_X', 'OSD1_RSSI_Y',
    'OSD1_ALTITUDE_EN', 'OSD1_MESSAGE_EN'
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

PARAMS_JSON=$(cat /tmp/params_out.json 2>/dev/null || echo '{"connected": false}')

# Package up result
cat > /tmp/task_result.json << JSONEOF
{
    "task_start": $TASK_START,
    "task_end": $(date +%s),
    "params": $PARAMS_JSON
}
JSONEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
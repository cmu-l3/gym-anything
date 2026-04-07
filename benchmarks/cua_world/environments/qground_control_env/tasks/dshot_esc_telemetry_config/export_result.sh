#!/bin/bash
echo "=== Exporting dshot_esc_telemetry_config result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Query all 7 parameters via pymavlink
python3 << 'PYEOF' > /tmp/params_out.json
import json, time, sys

TARGET_PARAMS = [
    'MOT_PWM_TYPE', 'SERIAL2_PROTOCOL', 'SERIAL2_BAUD',
    'SERVO_BLH_AUTO', 'SERVO_BLH_POLES', 'INS_HNTCH_ENABLE', 'INS_HNTCH_MODE'
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
    
    # Wait for heartbeat, accounting for potential recent reboot by the agent
    msg = master.recv_match(type='HEARTBEAT', blocking=True, timeout=20)
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
    # Print error json to stdout so it gets captured by the shell redirect
    print(json.dumps({p: None for p in TARGET_PARAMS} | {'connected': False, 'error': str(e)}))
PYEOF

PARAMS_JSON=$(cat /tmp/params_out.json 2>/dev/null || echo '{}')

cat > /tmp/task_result.json << JSONEOF
{
    "task_start": $TASK_START,
    "params": $PARAMS_JSON
}
JSONEOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="
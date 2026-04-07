#!/bin/bash
echo "=== Exporting high_altitude_density_tuning result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot as evidence
take_screenshot /tmp/task_end_screenshot.png

# Query the 6 specific aerodynamic parameters via pymavlink
python3 << 'PYEOF' > /tmp/params_out.json
import json, time, sys

TARGET_PARAMS = [
    'MOT_THST_HOVER', 
    'MOT_HOVER_LEARN', 
    'MOT_SPIN_ARM', 
    'MOT_SPIN_MIN', 
    'ATC_THR_MIX_MAN', 
    'MOT_YAW_HEADROOM'
]

def read_param(master, sysid, compid, pname, timeout=10):
    """Read a single param with robust filtering (handles QGC cross-talk)."""
    for attempt in range(3):
        master.mav.param_request_read_send(sysid, compid, pname.encode('utf-8'), -1)
        deadline = time.time() + timeout
        while time.time() < deadline:
            pmsg = master.recv_match(type='PARAM_VALUE', blocking=True, timeout=1)
            if pmsg and pmsg.param_id.strip('\x00') == pname:
                # ArduPilot sends floats which can be slightly imprecise (e.g. 0.1500000059)
                # We round to 4 decimal places to stabilize them
                return round(pmsg.param_value, 4)
        time.sleep(0.3)
    return None

try:
    from pymavlink import mavutil
    # Connect over TCP to SITL
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
    "task_start": $(cat /tmp/task_start_time 2>/dev/null || echo "0"),
    "task_end": $(date +%s),
    "params": $PARAMS_JSON
}
JSONEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
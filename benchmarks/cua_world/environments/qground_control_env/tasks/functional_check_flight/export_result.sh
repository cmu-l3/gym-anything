#!/bin/bash
echo "=== Exporting functional_check_flight result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

REPORT_FILE="/home/ga/Documents/QGC/check_flight_report.txt"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

REPORT_FOUND="false"
REPORT_MODIFIED="false"
REPORT_CONTENT='""'

# 2. Check Report File
if [ -f "$REPORT_FILE" ]; then
    REPORT_FOUND="true"
    REPORT_MTIME=$(stat -c%Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_MODIFIED="true"
    fi
    REPORT_CONTENT=$(cat "$REPORT_FILE" 2>/dev/null | python3 -c "
import sys, json
content = sys.stdin.read()
print(json.dumps(content))
" 2>/dev/null || echo '""')
fi

# 3. Query MAVLink for Flight Statistics
# Note: STAT_FLTTIME only updates in EEPROM on disarm, so if they are still flying it might be 0.
# We also check base_mode to see if currently armed.
python3 << 'PYEOF' > /tmp/mavlink_stats.json
import json, time
from pymavlink import mavutil

result = {'connected': False, 'is_armed': False, 'STAT_FLTTIME': 0, 'STAT_RUNTIME': 0}
try:
    master = mavutil.mavlink_connection('tcp:localhost:5762')
    msg = master.recv_match(type='HEARTBEAT', blocking=True, timeout=10)
    if msg:
        result['connected'] = True
        result['is_armed'] = (msg.base_mode & mavutil.mavlink.MAV_MODE_FLAG_SAFETY_ARMED) != 0

        # Request parameters
        for param in [b'STAT_FLTTIME', b'STAT_RUNTIME']:
            master.mav.param_request_read_send(master.target_system, master.target_component, param, -1)
            pmsg = master.recv_match(type='PARAM_VALUE', blocking=True, timeout=3)
            if pmsg:
                result[param.decode('utf-8')] = pmsg.param_value
except Exception as e:
    result['error'] = str(e)

print(json.dumps(result))
PYEOF

MAVLINK_JSON=$(cat /tmp/mavlink_stats.json 2>/dev/null || echo '{}')
INITIAL_JSON=$(cat /tmp/initial_stats.json 2>/dev/null || echo '{"STAT_FLTTIME": 0, "STAT_RUNTIME": 0}')

# 4. Compile final JSON
cat > /tmp/task_result.json << JSONEOF
{
    "report_found": $( [ "$REPORT_FOUND" = "true" ] && echo "true" || echo "false" ),
    "report_modified": $( [ "$REPORT_MODIFIED" = "true" ] && echo "true" || echo "false" ),
    "report_content": $REPORT_CONTENT,
    "initial_stats": $INITIAL_JSON,
    "final_stats": $MAVLINK_JSON
}
JSONEOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="
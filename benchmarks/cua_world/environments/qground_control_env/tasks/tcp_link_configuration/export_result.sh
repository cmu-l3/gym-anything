#!/bin/bash
set -e
echo "=== Exporting TCP Link Configuration results ==="

RESULT_FILE="/tmp/task_result.json"
QGC_INI="/home/ga/.config/QGroundControl/QGroundControl.ini"
REPORT_FILE="/home/ga/Documents/QGC/connection_report.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final_state.png 2>/dev/null || true

# 2. Gracefully kill QGC to force it to flush QGroundControl.ini to disk
echo "--- Forcing QGC to flush settings ---"
pkill -15 -f "QGroundControl" || true
sleep 3

# 3. Capture QGC INI contents securely via Python
echo "--- Reading QGC config ---"
QGC_INI_CONTENT=$(python3 -c 'import json, sys, os; print(json.dumps(open(sys.argv[1]).read()) if os.path.exists(sys.argv[1]) else "\"\"")' "$QGC_INI")
BASELINE_INI_CONTENT=$(python3 -c 'import json, sys, os; print(json.dumps(open(sys.argv[1]).read()) if os.path.exists(sys.argv[1]) else "\"\"")' "/tmp/qgc_baseline.ini")

QGC_INI_EXISTS="false"
if [ -f "$QGC_INI" ]; then
    QGC_INI_EXISTS="true"
fi

# 4. Test TCP:5762 MAVLink connectivity
echo "--- Testing TCP:5762 MAVLink connectivity ---"
python3 << 'PYEOF' > /tmp/tcp_test_result.json 2>&1 || true
import json
import time

try:
    from pymavlink import mavutil
    
    # Connect to SITL TCP port
    conn = mavutil.mavlink_connection('tcp:127.0.0.1:5762', timeout=10)
    
    # Wait for heartbeat
    msg = conn.wait_heartbeat(timeout=10)
    if msg:
        count = 1
        start = time.time()
        while time.time() - start < 3:
            msg2 = conn.recv_match(type='HEARTBEAT', blocking=True, timeout=1)
            if msg2:
                count += 1
        
        result = {
            "active": True,
            "heartbeat_count": count
        }
        print(json.dumps(result))
    else:
        print(json.dumps({"active": False, "heartbeat_count": 0}))
    conn.close()
except Exception as e:
    print(json.dumps({"active": False, "error": str(e)}))
PYEOF

TCP_TEST=$(cat /tmp/tcp_test_result.json 2>/dev/null || echo '{"active": false}')

# 5. Check report file
echo "--- Checking report file ---"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_SIZE=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
fi

REPORT_CONTENT=$(python3 -c 'import json, sys, os; print(json.dumps(open(sys.argv[1]).read()) if os.path.exists(sys.argv[1]) else "\"\"")' "$REPORT_FILE")

# 6. Build result JSON
echo "--- Building result JSON ---"
cat > "$RESULT_FILE" << EOF
{
    "task_start_time": $TASK_START,
    "qgc_ini": {
        "exists": $QGC_INI_EXISTS,
        "content": $QGC_INI_CONTENT
    },
    "baseline_ini": {
        "content": $BASELINE_INI_CONTENT
    },
    "tcp_connectivity": $TCP_TEST,
    "report": {
        "exists": $REPORT_EXISTS,
        "mtime": $REPORT_MTIME,
        "size": $REPORT_SIZE,
        "content": $REPORT_CONTENT
    }
}
EOF

echo "--- Result written to $RESULT_FILE ---"
echo "=== Export complete ==="
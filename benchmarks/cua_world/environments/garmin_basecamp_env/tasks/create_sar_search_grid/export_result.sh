#!/bin/bash
echo "=== Exporting SAR Search Grid task results ==="

# Define paths (using container paths for bash script)
START_TIME_FILE="/workspace/task_start_time.txt"
GPX_FILE="/workspace/output/sar_grid.gpx"
RESULT_JSON="/workspace/output/task_result.json"

TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot via PyAutoGUI server
python3 -c "
import socket, json
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2.0)
    s.connect(('127.0.0.1', 5555))
    s.sendall(json.dumps({'action': 'screenshot', 'path': 'C:\\\\workspace\\\\evidence\\\\task_final_state.png'}).encode('utf-8'))
    s.recv(4096)
    s.close()
except:
    pass
"

# Check GPX file properties
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"

if [ -f "$GPX_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$GPX_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$GPX_FILE" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Write result summary for the verifier
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME
}
EOF

echo "Task results exported."
cat "$RESULT_JSON"
echo "=== Export complete ==="
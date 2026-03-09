#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting SMTP Email Forensics Result ==="

# 1. Capture final screenshot
take_screenshot /tmp/task_final_state.png

# 2. Gather Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
REPORT_FILE="/home/ga/Documents/smtp_report.txt"
GROUND_TRUTH_DIR="/tmp/.smtp_ground_truth"

# 3. Read User Report
REPORT_EXISTS="false"
REPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    # Read content, limit size to prevent issues
    REPORT_CONTENT=$(head -n 50 "$REPORT_FILE")
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Read Ground Truth
GT_TOTAL=$(cat "$GROUND_TRUTH_DIR/total_packets" 2>/dev/null || echo "0")
GT_SMTP=$(cat "$GROUND_TRUTH_DIR/smtp_packets" 2>/dev/null || echo "0")
GT_SENDER=$(cat "$GROUND_TRUTH_DIR/sender" 2>/dev/null || echo "")
GT_RECIPIENT=$(cat "$GROUND_TRUTH_DIR/recipient" 2>/dev/null || echo "")
GT_SERVER=$(cat "$GROUND_TRUTH_DIR/smtp_server_ip" 2>/dev/null || echo "")
GT_CLIENT=$(cat "$GROUND_TRUTH_DIR/smtp_client_ip" 2>/dev/null || echo "")

# 5. Construct JSON Result
# Using python for safe JSON construction
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 -c "
import json
import sys

data = {
    'task_timing': {
        'start': int(sys.argv[1]),
        'end': int(sys.argv[2]),
        'duration': int(sys.argv[2]) - int(sys.argv[1])
    },
    'file_check': {
        'exists': sys.argv[3] == 'true',
        'created_during_task': sys.argv[4] == 'true',
        'path': '$REPORT_FILE'
    },
    'content': sys.argv[5],
    'ground_truth': {
        'total_packets': sys.argv[6],
        'smtp_packets': sys.argv[7],
        'sender': sys.argv[8],
        'recipient': sys.argv[9],
        'server_ip': sys.argv[10],
        'client_ip': sys.argv[11]
    }
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(data, f, indent=4)
" "$TASK_START" "$TASK_END" "$REPORT_EXISTS" "$FILE_CREATED_DURING_TASK" "$REPORT_CONTENT" \
  "$GT_TOTAL" "$GT_SMTP" "$GT_SENDER" "$GT_RECIPIENT" "$GT_SERVER" "$GT_CLIENT"

# 6. Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
#!/bin/bash
echo "=== Exporting TCP Flow Control Analysis Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

REPORT_FILE="/home/ga/Documents/captures/flow_control_report.txt"
GT_DIR="/var/lib/wireshark/ground_truth"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if report exists
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE")
    
    # Check creation time
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# Read Ground Truth values
GT_TOTAL=$(cat "$GT_DIR/total_packets" 2>/dev/null || echo "0")
GT_ZERO=$(cat "$GT_DIR/zero_window" 2>/dev/null || echo "0")
GT_UPDATE=$(cat "$GT_DIR/window_update" 2>/dev/null || echo "0")
GT_FULL=$(cat "$GT_DIR/window_full" 2>/dev/null || echo "0")
GT_MAX=$(cat "$GT_DIR/max_window" 2>/dev/null || echo "0")
GT_MIN=$(cat "$GT_DIR/min_window" 2>/dev/null || echo "0")
GT_CONV=$(cat "$GT_DIR/conversations" 2>/dev/null || echo "0")
GT_SYN=$(cat "$GT_DIR/syn_wscale" 2>/dev/null || echo "0")

# Parse User Values using regex
# We use Python for robust parsing of the structured text
# and constructing the JSON result
python3 -c "
import json
import re
import sys
import os

def extract_val(pattern, text):
    match = re.search(pattern, text, re.MULTILINE)
    if match:
        try:
            return int(match.group(1))
        except ValueError:
            return None
    return None

report_content = sys.stdin.read()
gt_data = {
    'total_packets': int('$GT_TOTAL'),
    'zero_window': int('$GT_ZERO'),
    'window_update': int('$GT_UPDATE'),
    'window_full': int('$GT_FULL'),
    'max_window': int('$GT_MAX'),
    'min_window': int('$GT_MIN'),
    'conversations': int('$GT_CONV'),
    'syn_wscale': int('$GT_SYN')
}

user_data = {
    'total_packets': extract_val(r'Total Packets:\s*(\d+)', report_content),
    'zero_window': extract_val(r'TCP Zero Window Events:\s*(\d+)', report_content),
    'window_update': extract_val(r'TCP Window Update Events:\s*(\d+)', report_content),
    'window_full': extract_val(r'TCP Window Full Events:\s*(\d+)', report_content),
    'max_window': extract_val(r'Max TCP Window Size:\s*(\d+)', report_content),
    'min_window': extract_val(r'Min Non-Zero TCP Window Size:\s*(\d+)', report_content),
    'conversations': extract_val(r'Unique TCP Conversations:\s*(\d+)', report_content),
    'syn_wscale': extract_val(r'SYN Packets with Window Scale Option:\s*(\d+)', report_content)
}

result = {
    'report_exists': '$REPORT_EXISTS' == 'true',
    'report_created_during_task': '$REPORT_CREATED_DURING_TASK' == 'true',
    'ground_truth': gt_data,
    'user_values': user_data,
    'report_content': report_content[:1000]  # First 1000 chars for debugging
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
" <<< "$REPORT_CONTENT"

# Move result to safe location if needed (verifier reads /tmp/task_result.json)
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="
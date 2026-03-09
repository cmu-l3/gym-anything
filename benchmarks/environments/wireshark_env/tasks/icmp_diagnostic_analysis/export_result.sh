#!/bin/bash
echo "=== Exporting Task Result ==="

# Paths
REPORT_FILE="/home/ga/Documents/icmp_analysis_report.txt"
GROUND_TRUTH_DIR="/var/lib/wireshark_task/ground_truth"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check Report File Status
FILE_EXISTS=false
FILE_CREATED_DURING_TASK=false
CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS=true
    # Read content safely, escape special json chars
    CONTENT=$(cat "$REPORT_FILE")
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK=true
    fi
fi

# 3. Read Ground Truth
GT_TOTAL=$(cat "$GROUND_TRUTH_DIR/total_count.txt" 2>/dev/null || echo "0")
GT_TYPE_COUNTS=$(cat "$GROUND_TRUTH_DIR/type_counts.json" 2>/dev/null || echo "{}")
GT_AVG_RTT=$(cat "$GROUND_TRUTH_DIR/avg_rtt.txt" 2>/dev/null || echo "0")
GT_HOPS=$(cat "$GROUND_TRUTH_DIR/unique_hops.txt" 2>/dev/null || echo "0")
GT_UNREACHABLE=$(cat "$GROUND_TRUTH_DIR/unreachable_ips.txt" 2>/dev/null || echo "")

# 4. Construct JSON Result using Python
# We use Python to handle the JSON formatting and escaping properly
python3 -c "
import json
import os
import sys

try:
    content = sys.argv[1]
    
    # Construct the result object
    result = {
        'file_exists': $FILE_EXISTS,
        'created_during_task': $FILE_CREATED_DURING_TASK,
        'report_content': content,
        'ground_truth': {
            'total_count': int('$GT_TOTAL'),
            'type_counts': json.loads('$GT_TYPE_COUNTS'),
            'avg_rtt': float('$GT_AVG_RTT'),
            'unique_hops': int('$GT_HOPS'),
            'unreachable_ips': '$GT_UNREACHABLE'
        },
        'timestamp': '$(date -Iseconds)'
    }
    
    # Write to temp file
    with open('/tmp/temp_result.json', 'w') as f:
        json.dump(result, f, indent=2)

except Exception as e:
    print(f'Error constructing JSON: {e}', file=sys.stderr)
    sys.exit(1)
" "$CONTENT"

# Move result to final location
mv /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
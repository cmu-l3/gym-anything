#!/bin/bash
set -e
echo "=== Exporting I/O Statistics Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

REPORT_FILE="/home/ga/Documents/captures/io_stats_report.txt"
GT_DIR="/var/lib/wireshark_ground_truth"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check if report exists and was created during task
REPORT_EXISTS="false"
REPORT_FRESH="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START_TIME" ]; then
        REPORT_FRESH="true"
    fi
    # Read content safely, verify it's text
    if file "$REPORT_FILE" | grep -q "text"; then
        REPORT_CONTENT=$(cat "$REPORT_FILE" | base64 -w 0)
    fi
fi

# Read Ground Truth values (script runs as root so it can read from /var/lib/wireshark_ground_truth)
GT_TOTAL_PACKETS=$(cat "$GT_DIR/total_packets.txt" 2>/dev/null || echo "0")
GT_DURATION=$(cat "$GT_DIR/capture_duration.txt" 2>/dev/null || echo "0")
GT_TOTAL_BYTES=$(cat "$GT_DIR/total_bytes.txt" 2>/dev/null || echo "0")
GT_AVG_PPS=$(cat "$GT_DIR/avg_pps.txt" 2>/dev/null || echo "0")
GT_BUSIEST_START=$(cat "$GT_DIR/busiest_start.txt" 2>/dev/null || echo "0")
GT_BUSIEST_PACKETS=$(cat "$GT_DIR/busiest_packets.txt" 2>/dev/null || echo "0")

# Check if Wireshark is running
APP_RUNNING=$(pgrep -f "wireshark" > /dev/null && echo "true" || echo "false")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json, sys

data = {
    'task_start': int(sys.argv[1]),
    'report_exists': sys.argv[2] == 'true',
    'report_fresh': sys.argv[3] == 'true',
    'report_content_b64': sys.argv[4],
    'app_running': sys.argv[5] == 'true',
    'ground_truth': {
        'total_packets': int(sys.argv[6]),
        'duration': float(sys.argv[7]),
        'total_bytes': int(sys.argv[8]),
        'avg_pps': float(sys.argv[9]),
        'busiest_start': float(sys.argv[10]),
        'busiest_packets': int(sys.argv[11])
    },
    'screenshot_path': '/tmp/task_final.png'
}

with open(sys.argv[12], 'w') as f:
    json.dump(data, f)
" "$TASK_START_TIME" "$REPORT_EXISTS" "$REPORT_FRESH" "$REPORT_CONTENT" "$APP_RUNNING" \
  "$GT_TOTAL_PACKETS" "$GT_DURATION" "$GT_TOTAL_BYTES" "$GT_AVG_PPS" \
  "$GT_BUSIEST_START" "$GT_BUSIEST_PACKETS" "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
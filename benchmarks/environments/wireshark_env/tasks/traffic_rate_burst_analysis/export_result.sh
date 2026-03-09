#!/bin/bash
set -e

echo "=== Exporting Traffic Rate Analysis Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Collect Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_FILE="/home/ga/Documents/traffic_rate_report.txt"
PCAP_FILE="/home/ga/Documents/captures/200722_tcp_anon.pcapng"

REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_SIZE=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_FILE")
    REPORT_MTIME=$(stat -c%Y "$REPORT_FILE")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if Wireshark is still running
APP_RUNNING="false"
if pgrep -f wireshark > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create Result JSON
# We don't read the file content here; the verifier will copy the file out.
# We just provide metadata.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_size_bytes": $REPORT_SIZE,
    "report_path": "$REPORT_FILE",
    "ground_truth_path": "/var/lib/wireshark/ground_truth.json",
    "app_was_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# 5. Save JSON safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
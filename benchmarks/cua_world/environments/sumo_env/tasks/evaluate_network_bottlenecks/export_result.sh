#!/bin/bash
echo "=== Exporting evaluate_network_bottlenecks result ==="

source /workspace/scripts/task_utils.sh

# Record task end
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check output files
QUEUES_FILE="/home/ga/SUMO_Output/queues.xml"
STATS_FILE="/home/ga/SUMO_Output/stats.xml"
REPORT_FILE="/home/ga/SUMO_Output/bottleneck_report.txt"

QUEUES_EXISTS="false"
QUEUES_CREATED_DURING="false"
if [ -f "$QUEUES_FILE" ]; then
    QUEUES_EXISTS="true"
    MTIME=$(stat -c %Y "$QUEUES_FILE")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        QUEUES_CREATED_DURING="true"
    fi
fi

STATS_EXISTS="false"
STATS_CREATED_DURING="false"
if [ -f "$STATS_FILE" ]; then
    STATS_EXISTS="true"
    MTIME=$(stat -c %Y "$STATS_FILE")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        STATS_CREATED_DURING="true"
    fi
fi

REPORT_EXISTS="false"
REPORT_CREATED_DURING="false"
REPORT_CONTENT="null"
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    MTIME=$(stat -c %Y "$REPORT_FILE")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
    # Read the report content safely into JSON string
    REPORT_CONTENT=$(cat "$REPORT_FILE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""')
fi

# Retrieve ground truth
if [ -f /root/.bologna_baseline_gt.json ]; then
    GT_JSON=$(cat /root/.bologna_baseline_gt.json)
else
    GT_JSON="{}"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "queues_exists": $QUEUES_EXISTS,
    "queues_created_during_task": $QUEUES_CREATED_DURING,
    "stats_exists": $STATS_EXISTS,
    "stats_created_during_task": $STATS_CREATED_DURING,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING,
    "report_content": $REPORT_CONTENT,
    "ground_truth": $GT_JSON
}
EOF

# Move to final location securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="
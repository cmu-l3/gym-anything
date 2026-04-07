#!/bin/bash
echo "=== Exporting Clinical Data ETL Pipeline Result ==="

source /workspace/scripts/task_utils.sh

# Paths
LOG_FILE="/home/ga/openice/logs/openice.log"
AGENT_CSV="/home/ga/Desktop/vital_signs_dataset.csv"
GROUND_TRUTH_CSV="/tmp/ground_truth_extract.csv"

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final_screenshot.png

# 2. Extract Ground Truth Data from Logs
# We parse the actual logs generated during the task to verify the agent's CSV content.
# We look for standard OpenICE metric identifiers.
# Note: This regex assumes a standard log format. We try to be flexible.
# Typical log line: 2023-10-27 10:00:01 INFO ... MDC_ECG_HEART_RATE value=72 ...

INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
echo "Extracting ground truth from new log lines (bytes ${INITIAL_LOG_SIZE}+)..."

# Create header for GT
echo "Timestamp,Metric,Value" > "$GROUND_TRUTH_CSV"

# Parse Heart Rate (MDC_ECG_HEART_RATE or MDC_PULS_RATE)
tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null | \
grep -E "MDC_ECG_HEART_RATE|MDC_PULS_RATE" | \
grep -E "Numeric" | \
while read -r line; do
    # Extract timestamp (first 23 chars usually)
    TS=$(echo "$line" | cut -d' ' -f1,2)
    # Extract value (naive parsing looking for digits after patterns)
    # This is a heuristic; simulator logs vary. We look for the numeric value associated with the metric.
    VAL=$(echo "$line" | grep -oE "value=[0-9.]+" | cut -d'=' -f2)
    if [ ! -z "$VAL" ]; then
        echo "$TS,HeartRate,$VAL" >> "$GROUND_TRUTH_CSV"
    fi
done

# Parse SpO2 (MDC_PULS_OXIM_SAT_O2)
tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null | \
grep -E "MDC_PULS_OXIM_SAT_O2" | \
grep -E "Numeric" | \
while read -r line; do
    TS=$(echo "$line" | cut -d' ' -f1,2)
    VAL=$(echo "$line" | grep -oE "value=[0-9.]+" | cut -d'=' -f2)
    if [ ! -z "$VAL" ]; then
        echo "$TS,SpO2,$VAL" >> "$GROUND_TRUTH_CSV"
    fi
done

GT_ROW_COUNT=$(wc -l < "$GROUND_TRUTH_CSV")
echo "Ground truth rows extracted: $GT_ROW_COUNT"

# 3. Check Agent's CSV
CSV_EXISTS="false"
CSV_ROWS=0
CSV_MTIME=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$AGENT_CSV" ]; then
    CSV_EXISTS="true"
    CSV_ROWS=$(wc -l < "$AGENT_CSV")
    CSV_MTIME=$(stat -c %Y "$AGENT_CSV" 2>/dev/null || echo "0")
    
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Copy agent CSV for verification script to access
    cp "$AGENT_CSV" /tmp/agent_output.csv
    chmod 666 /tmp/agent_output.csv
else
    # Create dummy file if not exists to prevent copy errors
    touch /tmp/agent_output.csv
fi

# 4. Check for Device Activity (Secondary Verification)
# Count active simulated devices via window title or logs
DEVICE_COUNT=0
if grep -q "Simulated Multiparameter Monitor" "$LOG_FILE"; then DEVICE_COUNT=$((DEVICE_COUNT+1)); fi
if grep -q "Simulated Pulse Oximeter" "$LOG_FILE"; then DEVICE_COUNT=$((DEVICE_COUNT+1)); fi

# 5. Create Result JSON
create_result_json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_created_during_task": $FILE_CREATED_DURING_TASK,
    "device_evidence_count": $DEVICE_COUNT,
    "ground_truth_rows": $GT_ROW_COUNT,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

# Ensure permissions
chmod 666 "$GROUND_TRUTH_CSV" 2>/dev/null || true
chmod 666 /tmp/agent_output.csv 2>/dev/null || true
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json
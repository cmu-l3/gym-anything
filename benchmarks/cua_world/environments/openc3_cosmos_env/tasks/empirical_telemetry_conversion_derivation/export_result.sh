#!/bin/bash
echo "=== Exporting Empirical Telemetry Conversion Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/ivv_task_start_ts 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Desktop/ivv_conversion_report.json"

FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_MTIME="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW="true"
    fi
fi

# Sample live telemetry to verify the required final state
# TEMP3 should be locked to 85.0. TEMP1 and TEMP2 should be fluctuating (normalized).
echo "Sampling initial telemetry states..."
T1_A=$(cosmos_tlm "INST HEALTH_STATUS TEMP1" 2>/dev/null || echo "0")
T2_A=$(cosmos_tlm "INST HEALTH_STATUS TEMP2" 2>/dev/null || echo "0")
T3_A=$(cosmos_tlm "INST HEALTH_STATUS TEMP3" 2>/dev/null || echo "0")

echo "Waiting 3 seconds to test for normalization fluctuations..."
sleep 3

T1_B=$(cosmos_tlm "INST HEALTH_STATUS TEMP1" 2>/dev/null || echo "0")
T2_B=$(cosmos_tlm "INST HEALTH_STATUS TEMP2" 2>/dev/null || echo "0")
T3_B=$(cosmos_tlm "INST HEALTH_STATUS TEMP3" 2>/dev/null || echo "0")

echo "TEMP1: $T1_A -> $T1_B"
echo "TEMP2: $T2_A -> $T2_B"
echo "TEMP3: $T3_A -> $T3_B"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/ivv_task_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/ivv_task_end.png 2>/dev/null || true

# Safely create export JSON
TEMP_JSON=$(mktemp /tmp/ivv_export.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "telemetry_samples": {
        "t1_a": "$T1_A",
        "t1_b": "$T1_B",
        "t2_a": "$T2_A",
        "t2_b": "$T2_B",
        "t3_a": "$T3_A",
        "t3_b": "$T3_B"
    }
}
EOF

# Move to final readable location
cp "$TEMP_JSON" /tmp/ivv_export_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/ivv_export_result.json
chmod 666 /tmp/ivv_export_result.json 2>/dev/null || sudo chmod 666 /tmp/ivv_export_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
#!/bin/bash
echo "=== Exporting Telemetry Override Test Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/telemetry_override_start_ts 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/override_test_report.json"

FILE_EXISTS=false
FILE_IS_NEW=false
FILE_MTIME=0

if [ -f "$OUTPUT" ]; then
    FILE_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$OUTPUT" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW=true
    fi
fi

# ================================================================
# VITAL ANTI-GAMING CHECK: Query actual telemetry state via API
# ================================================================
echo "Querying current TEMP1 and TEMP2 values from COSMOS API..."

# Wait a moment for any last-second normalizations to take effect
sleep 2

# Read TEMP1 (should be exactly 42.0 if override is active)
TEMP1_VAL=$(cosmos_tlm "INST HEALTH_STATUS TEMP1" 2>/dev/null || echo "null")
echo "Current TEMP1: $TEMP1_VAL"

# Read TEMP2 (should NOT be -15.5 if properly normalized)
TEMP2_VAL=$(cosmos_tlm "INST HEALTH_STATUS TEMP2" 2>/dev/null || echo "null")
echo "Current TEMP2: $TEMP2_VAL"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/telemetry_override_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/telemetry_override_end.png 2>/dev/null || true

cat > /tmp/telemetry_override_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "api_temp1": "$TEMP1_VAL",
    "api_temp2": "$TEMP2_VAL"
}
EOF

echo "Export metadata saved to /tmp/telemetry_override_result.json"
echo "=== Export Complete ==="
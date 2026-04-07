#!/bin/bash
echo "=== Exporting System Readiness Audit Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/system_readiness_audit_start_ts 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/system_readiness.json"

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

# Get ground truth from COSMOS API
TARGETS_JSON=$(cosmos_api "get_target_names" '""' 2>/dev/null | jq -c '.result // ["INST", "INST2"]' 2>/dev/null || echo '["INST", "INST2"]')

# Read telemetry to prove system is alive during export
TEMP1_VAL=$(cosmos_tlm "INST HEALTH_STATUS TEMP1" 2>/dev/null || echo "0.0")
TEMP2_VAL=$(cosmos_tlm "INST HEALTH_STATUS TEMP2" 2>/dev/null || echo "0.0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/system_readiness_audit_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/system_readiness_audit_end.png 2>/dev/null || true

# Save result JSON safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "ground_truth_targets": $TARGETS_JSON,
    "current_temp1": $TEMP1_VAL,
    "current_temp2": $TEMP2_VAL
}
EOF

rm -f /tmp/system_readiness_audit_result.json 2>/dev/null || sudo rm -f /tmp/system_readiness_audit_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/system_readiness_audit_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/system_readiness_audit_result.json
chmod 666 /tmp/system_readiness_audit_result.json 2>/dev/null || sudo chmod 666 /tmp/system_readiness_audit_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "=== Export Complete ==="
#!/bin/bash
echo "=== Exporting Thermal Commissioning Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="thermal_commissioning"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/commissioning_report.json"

# ── Check output file existence and freshness ─────────────────────
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

# ── Query post-task system state ──────────────────────────────────

# INST2_INT interface state (was it reconnected?)
# Use get_interface (interface_state is restricted in OpenC3 6.x)
INST2_STATE=$(cosmos_api "get_interface" '"INST2_INT"' 2>/dev/null \
    | jq -r '.result.state // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")

# Current TEMP3 value (was the override removed?)
CURRENT_TEMP3=$(cosmos_tlm "INST HEALTH_STATUS TEMP3" 2>/dev/null | tr -d '"' || echo "UNKNOWN")

# Current limits for all 4 sensors (were they reconfigured?)
LIMITS_TEMP1=$(cosmos_api "get_limits" '"INST","HEALTH_STATUS","TEMP1"' 2>/dev/null | jq -c '.result // []' 2>/dev/null || echo "[]")
LIMITS_TEMP2=$(cosmos_api "get_limits" '"INST","HEALTH_STATUS","TEMP2"' 2>/dev/null | jq -c '.result // []' 2>/dev/null || echo "[]")
LIMITS_TEMP3=$(cosmos_api "get_limits" '"INST","HEALTH_STATUS","TEMP3"' 2>/dev/null | jq -c '.result // []' 2>/dev/null || echo "[]")
LIMITS_TEMP4=$(cosmos_api "get_limits" '"INST","HEALTH_STATUS","TEMP4"' 2>/dev/null | jq -c '.result // []' 2>/dev/null || echo "[]")

# Read original limits for comparison
ORIG_TEMP1=$(cat /tmp/${TASK_NAME}_orig_limits_TEMP1.json 2>/dev/null || echo "[]")
ORIG_TEMP2=$(cat /tmp/${TASK_NAME}_orig_limits_TEMP2.json 2>/dev/null || echo "[]")
ORIG_TEMP3=$(cat /tmp/${TASK_NAME}_orig_limits_TEMP3.json 2>/dev/null || echo "[]")
ORIG_TEMP4=$(cat /tmp/${TASK_NAME}_orig_limits_TEMP4.json 2>/dev/null || echo "[]")

# ── Take final screenshot ─────────────────────────────────────────
take_screenshot /tmp/${TASK_NAME}_final.png

# ── Write result JSON ─────────────────────────────────────────────
cat > /tmp/${TASK_NAME}_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "post_task_state": {
        "inst2_int_state": "$INST2_STATE",
        "current_temp3": "$CURRENT_TEMP3"
    },
    "current_limits": {
        "TEMP1": $LIMITS_TEMP1,
        "TEMP2": $LIMITS_TEMP2,
        "TEMP3": $LIMITS_TEMP3,
        "TEMP4": $LIMITS_TEMP4
    },
    "original_limits": {
        "TEMP1": $ORIG_TEMP1,
        "TEMP2": $ORIG_TEMP2,
        "TEMP3": $ORIG_TEMP3,
        "TEMP4": $ORIG_TEMP4
    }
}
EOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "INST2_INT state: $INST2_STATE"
echo "Current TEMP3: $CURRENT_TEMP3"
echo "=== Export Complete ==="

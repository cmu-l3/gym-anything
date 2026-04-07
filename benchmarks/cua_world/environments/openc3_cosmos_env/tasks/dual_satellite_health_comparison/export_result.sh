#!/bin/bash
echo "=== Exporting Dual-Satellite Health Comparison Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/dual_satellite_health_comparison_start_ts 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/health_comparison.json"

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

# Check if both targets are actually active via COSMOS API (Cross-validation check)
INST1_ACTIVE=false
INST2_ACTIVE=false
if cosmos_tlm "INST HEALTH_STATUS TEMP1" >/dev/null 2>&1; then 
    INST1_ACTIVE=true 
fi
if cosmos_tlm "INST2 HEALTH_STATUS TEMP1" >/dev/null 2>&1; then 
    INST2_ACTIVE=true 
fi

# Take final screenshot
DISPLAY=:1 import -window root /tmp/dual_satellite_health_comparison_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/dual_satellite_health_comparison_end.png 2>/dev/null || true

# Export metadata
cat > /tmp/dual_satellite_health_comparison_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "inst1_active": $INST1_ACTIVE,
    "inst2_active": $INST2_ACTIVE
}
EOF

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "INST1 active: $INST1_ACTIVE"
echo "INST2 active: $INST2_ACTIVE"
echo "=== Export Complete ==="
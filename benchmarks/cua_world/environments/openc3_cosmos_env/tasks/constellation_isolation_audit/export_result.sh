#!/bin/bash
echo "=== Exporting Constellation Isolation Audit Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/isolation_audit_start_ts 2>/dev/null || echo "0")
INST_INITIAL=$(cat /tmp/isolation_audit_inst_initial 2>/dev/null || echo "0")
INST2_INITIAL=$(cat /tmp/isolation_audit_inst2_initial 2>/dev/null || echo "0")

OUTPUT="/home/ga/Desktop/isolation_audit.json"

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

# Fetch LIVE end-of-task telemetry counters to verify the agent actually sent commands
echo "Fetching live final counters..."
INST_LIVE_FINAL=$(cosmos_tlm "INST HEALTH_STATUS COLLECTS" 2>/dev/null || echo "0")
INST2_LIVE_FINAL=$(cosmos_tlm "INST2 HEALTH_STATUS COLLECTS" 2>/dev/null || echo "0")

echo "INST Live Initial: $INST_INITIAL -> Final: $INST_LIVE_FINAL"
echo "INST2 Live Initial: $INST2_INITIAL -> Final: $INST2_LIVE_FINAL"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/isolation_audit_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/isolation_audit_end.png 2>/dev/null || true

# Export JSON metadata for python verifier
cat > /tmp/constellation_isolation_audit_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "live_inst_initial": "$INST_INITIAL",
    "live_inst2_initial": "$INST2_INITIAL",
    "live_inst_final": "$INST_LIVE_FINAL",
    "live_inst2_final": "$INST2_LIVE_FINAL"
}
EOF

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "=== Export Complete ==="
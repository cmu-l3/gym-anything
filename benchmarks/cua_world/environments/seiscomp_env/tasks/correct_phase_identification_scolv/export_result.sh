#!/bin/bash
echo "=== Exporting correct_phase_identification_scolv results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if scolv is running
SCOLV_RUNNING=$(pgrep -f "scolv" > /dev/null && echo "true" || echo "false")

# Extract final database state
EVENT_ID=$(mysql -u sysop -psysop seiscomp -N -e "SELECT publicID FROM Event LIMIT 1" 2>/dev/null)
ORIGIN_ID=$(mysql -u sysop -psysop seiscomp -N -e "SELECT preferredOriginID FROM Event WHERE publicID='$EVENT_ID'" 2>/dev/null)

# Get Origin creation time
ORIGIN_MTIME_STR=$(mysql -u sysop -psysop seiscomp -N -e "SELECT creationInfo_creationTime FROM Origin WHERE publicID='$ORIGIN_ID'" 2>/dev/null)
if [ -z "$ORIGIN_MTIME_STR" ] || [ "$ORIGIN_MTIME_STR" = "NULL" ]; then
    # Try alternate column name just in case
    ORIGIN_MTIME_STR=$(mysql -u sysop -psysop seiscomp -N -e "SELECT m_creationInfo_creationTime FROM Origin WHERE publicID='$ORIGIN_ID'" 2>/dev/null)
fi

ORIGIN_MTIME=0
if [ -n "$ORIGIN_MTIME_STR" ] && [ "$ORIGIN_MTIME_STR" != "NULL" ]; then
    ORIGIN_MTIME=$(date -d "$ORIGIN_MTIME_STR" +%s 2>/dev/null || echo "0")
fi

# Get Phase for TOLI
TOLI_PHASE=$(mysql -u sysop -psysop seiscomp -N -e "
SELECT a.phase 
FROM Arrival a 
JOIN Pick p ON a.pickID = p.publicID 
WHERE a.originID = '$ORIGIN_ID' 
AND p.waveformID_stationCode = 'TOLI'
LIMIT 1
" 2>/dev/null)

# Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "scolv_running": $SCOLV_RUNNING,
    "event_id": "$EVENT_ID",
    "preferred_origin_id": "$ORIGIN_ID",
    "origin_creation_time": $ORIGIN_MTIME,
    "toli_phase": "$TOLI_PHASE"
}
EOF

# Save JSON safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo "=== Export complete ==="
#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_PICK_COUNT=$(cat /tmp/initial_toli_pick_count 2>/dev/null || echo "0")

# 1. Check for newly created manual picks for TOLI
CURRENT_PICK_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Pick WHERE waveformID_stationCode='TOLI'" 2>/dev/null || echo "0")

PICK_CREATED="false"
PICK_ID=""
PICK_PHASE=""

if [ "$CURRENT_PICK_COUNT" -gt "$INITIAL_PICK_COUNT" ]; then
    PICK_CREATED="true"
    # Get the latest pick
    LATEST_PICK=$(seiscomp_db_query "SELECT publicID, phaseCode FROM Pick WHERE waveformID_stationCode='TOLI' ORDER BY _oid DESC LIMIT 1" 2>/dev/null)
    PICK_ID=$(echo "$LATEST_PICK" | cut -f1)
    PICK_PHASE=$(echo "$LATEST_PICK" | cut -f2)
fi

# 2. Extract Event Preferred Origin Information
EVENT_INFO=$(seiscomp_db_query "SELECT publicID, preferredOriginID FROM Event ORDER BY _oid DESC LIMIT 1" 2>/dev/null)
EVENT_ID=$(echo "$EVENT_INFO" | cut -f1)
PREFERRED_ORIGIN=$(echo "$EVENT_INFO" | cut -f2)

ORIGIN_CREATED="false"
EVENT_UPDATED="false"

if [ "$PICK_CREATED" = "true" ] && [ -n "$PICK_ID" ]; then
    # Check if this new pick is associated with any origin (verifies Relocate was pressed)
    NEW_ORIGINS_COUNT=$(seiscomp_db_query "SELECT COUNT(DISTINCT originID) FROM Arrival WHERE pickID='$PICK_ID'" 2>/dev/null || echo "0")
    if [ "$NEW_ORIGINS_COUNT" -gt "0" ]; then
        ORIGIN_CREATED="true"
    fi
    
    # Check if this new pick is in the EVENT'S preferred origin (verifies Commit was pressed)
    if [ -n "$PREFERRED_ORIGIN" ]; then
        HAS_ARRIVAL=$(seiscomp_db_query "SELECT COUNT(*) FROM Arrival WHERE originID='$PREFERRED_ORIGIN' AND pickID='$PICK_ID'" 2>/dev/null || echo "0")
        if [ "$HAS_ARRIVAL" -gt "0" ]; then
            EVENT_UPDATED="true"
        fi
    fi
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Construct JSON output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "initial_pick_count": $INITIAL_PICK_COUNT,
    "current_pick_count": $CURRENT_PICK_COUNT,
    "pick_created": $PICK_CREATED,
    "pick_id": "$PICK_ID",
    "pick_phase": "$PICK_PHASE",
    "origin_created": $ORIGIN_CREATED,
    "event_updated": $EVENT_UPDATED,
    "preferred_origin": "$PREFERRED_ORIGIN"
}
EOF

# Move securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
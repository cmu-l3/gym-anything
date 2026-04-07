#!/bin/bash
echo "=== Exporting inject_origin_trigger_pipeline result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# ─── 1. Check if scevent is running ──────────────────────────────────────────
SCEVENT_RUNNING="false"
if su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
    LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
    seiscomp status scevent 2>/dev/null" | grep -q "is running"; then
    SCEVENT_RUNNING="true"
fi

# ─── 2. Read agent's output file ─────────────────────────────────────────────
AGENT_FILE="/home/ga/Documents/new_event_id.txt"
OUTPUT_EXISTS="false"
AGENT_EVENT_ID=""

if [ -f "$AGENT_FILE" ]; then
    OUTPUT_EXISTS="true"
    # Read the first line and trim any whitespace/newlines
    AGENT_EVENT_ID=$(cat "$AGENT_FILE" | tr -d '[:space:]' | head -n 1)
fi

# ─── 3. Query Database for Ground Truth ──────────────────────────────────────
TARGET_ORIGIN="Origin/20240101083015.123456.PARTNER"

# Find if the event was actually created by the pipeline for this origin
DB_EVENT=$(mysql -u sysop -psysop seiscomp -N -B -e "SELECT publicID, creationInfo_agencyID FROM Event WHERE preferredOriginID='$TARGET_ORIGIN' ORDER BY _oid DESC LIMIT 1" 2>/dev/null)

DB_PUBLIC_ID=""
DB_AGENCY_ID=""

if [ -n "$DB_EVENT" ]; then
    DB_PUBLIC_ID=$(echo "$DB_EVENT" | cut -f1)
    DB_AGENCY_ID=$(echo "$DB_EVENT" | cut -f2)
fi

# ─── 4. Export JSON Result ───────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "scevent_running": $SCEVENT_RUNNING,
    "output_exists": $OUTPUT_EXISTS,
    "agent_event_id": "$AGENT_EVENT_ID",
    "db_public_id": "$DB_PUBLIC_ID",
    "db_agency_id": "$DB_AGENCY_ID",
    "target_origin": "$TARGET_ORIGIN",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safely copy to /tmp accessible by the framework
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
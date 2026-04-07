#!/bin/bash
# Export script for Document Drug Allergy task
# Queries database for allergy record and exports verification data

echo "=== Exporting Document Drug Allergy Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot first
take_screenshot /tmp/task_final_state.png
echo "Final screenshot saved to /tmp/task_final_state.png"

# Target patient
PATIENT_PID=5

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial allergy count
INITIAL_ALLERGY_COUNT=$(cat /tmp/initial_allergy_count.txt 2>/dev/null || echo "0")

# Get current allergy count
CURRENT_ALLERGY_COUNT=$(openemr_query "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND type='allergy'" 2>/dev/null || echo "0")

echo "Allergy count: initial=$INITIAL_ALLERGY_COUNT, current=$CURRENT_ALLERGY_COUNT"

# Query for Penicillin allergy for this patient
# Use case-insensitive matching for "penicillin" or "pcn"
echo ""
echo "=== Querying for Penicillin allergy ==="
ALLERGY_DATA=$(openemr_query "SELECT id, pid, title, reaction, severity_al, begdate, UNIX_TIMESTAMP(date) as created_ts, activity FROM lists WHERE pid=$PATIENT_PID AND type='allergy' AND (LOWER(title) LIKE '%penicillin%' OR LOWER(title) LIKE '%pcn%') ORDER BY id DESC LIMIT 1" 2>/dev/null)

echo "Query result: $ALLERGY_DATA"

# Parse allergy data
ALLERGY_FOUND="false"
ALLERGY_ID=""
ALLERGY_TITLE=""
ALLERGY_REACTION=""
ALLERGY_SEVERITY=""
ALLERGY_BEGDATE=""
ALLERGY_CREATED_TS="0"
ALLERGY_ACTIVITY=""

if [ -n "$ALLERGY_DATA" ]; then
    ALLERGY_FOUND="true"
    # Parse tab-separated values
    ALLERGY_ID=$(echo "$ALLERGY_DATA" | cut -f1)
    ALLERGY_PID=$(echo "$ALLERGY_DATA" | cut -f2)
    ALLERGY_TITLE=$(echo "$ALLERGY_DATA" | cut -f3)
    ALLERGY_REACTION=$(echo "$ALLERGY_DATA" | cut -f4)
    ALLERGY_SEVERITY=$(echo "$ALLERGY_DATA" | cut -f5)
    ALLERGY_BEGDATE=$(echo "$ALLERGY_DATA" | cut -f6)
    ALLERGY_CREATED_TS=$(echo "$ALLERGY_DATA" | cut -f7)
    ALLERGY_ACTIVITY=$(echo "$ALLERGY_DATA" | cut -f8)
    
    echo ""
    echo "Penicillin allergy found:"
    echo "  ID: $ALLERGY_ID"
    echo "  Title: $ALLERGY_TITLE"
    echo "  Reaction: $ALLERGY_REACTION"
    echo "  Severity: $ALLERGY_SEVERITY"
    echo "  Begin Date: $ALLERGY_BEGDATE"
    echo "  Created Timestamp: $ALLERGY_CREATED_TS"
    echo "  Activity: $ALLERGY_ACTIVITY"
else
    echo "No Penicillin allergy found for patient"
fi

# Check if allergy was created after task start (anti-gaming)
CREATED_DURING_TASK="false"
if [ -n "$ALLERGY_CREATED_TS" ] && [ "$ALLERGY_CREATED_TS" != "0" ] && [ "$ALLERGY_CREATED_TS" != "NULL" ]; then
    if [ "$ALLERGY_CREATED_TS" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
        echo "Allergy was created during task execution (timestamp valid)"
    else
        echo "WARNING: Allergy timestamp ($ALLERGY_CREATED_TS) is before task start ($TASK_START)"
    fi
fi

# Check if this is a NEW allergy (count increased)
NEW_ALLERGY_ADDED="false"
if [ "$CURRENT_ALLERGY_COUNT" -gt "$INITIAL_ALLERGY_COUNT" ]; then
    NEW_ALLERGY_ADDED="true"
    echo "New allergy was added (count increased from $INITIAL_ALLERGY_COUNT to $CURRENT_ALLERGY_COUNT)"
fi

# Debug: Show all allergies for patient
echo ""
echo "=== All allergies for patient $PATIENT_PID ==="
openemr_query "SELECT id, title, reaction, severity_al, date FROM lists WHERE pid=$PATIENT_PID AND type='allergy' ORDER BY id DESC" 2>/dev/null
echo ""

# Check for pre-existing allergy
PRE_EXISTING=$(cat /tmp/existing_pcn_allergy.txt 2>/dev/null || echo "")
WAS_PRE_EXISTING="false"
if [ -n "$PRE_EXISTING" ]; then
    WAS_PRE_EXISTING="true"
fi

# Escape special characters for JSON
ALLERGY_TITLE_ESCAPED=$(echo "$ALLERGY_TITLE" | sed 's/"/\\"/g' | tr '\n' ' ')
ALLERGY_REACTION_ESCAPED=$(echo "$ALLERGY_REACTION" | sed 's/"/\\"/g' | tr '\n' ' ')
ALLERGY_SEVERITY_ESCAPED=$(echo "$ALLERGY_SEVERITY" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/allergy_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_allergy_count": $INITIAL_ALLERGY_COUNT,
    "current_allergy_count": $CURRENT_ALLERGY_COUNT,
    "new_allergy_added": $NEW_ALLERGY_ADDED,
    "allergy_found": $ALLERGY_FOUND,
    "created_during_task": $CREATED_DURING_TASK,
    "was_pre_existing": $WAS_PRE_EXISTING,
    "allergy": {
        "id": "$ALLERGY_ID",
        "title": "$ALLERGY_TITLE_ESCAPED",
        "reaction": "$ALLERGY_REACTION_ESCAPED",
        "severity": "$ALLERGY_SEVERITY_ESCAPED",
        "begdate": "$ALLERGY_BEGDATE",
        "created_timestamp": $ALLERGY_CREATED_TS,
        "activity": "$ALLERGY_ACTIVITY"
    },
    "screenshots": {
        "initial": "/tmp/task_initial_state.png",
        "final": "/tmp/task_final_state.png"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final location
rm -f /tmp/document_allergy_result.json 2>/dev/null || sudo rm -f /tmp/document_allergy_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/document_allergy_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/document_allergy_result.json
chmod 666 /tmp/document_allergy_result.json 2>/dev/null || sudo chmod 666 /tmp/document_allergy_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/document_allergy_result.json"
cat /tmp/document_allergy_result.json

echo ""
echo "=== Export Complete ==="
#!/bin/bash
# Export script for Update Allergy Severity task

echo "=== Exporting Update Allergy Severity Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png
echo "Final screenshot saved to /tmp/task_final_state.png"

# Target patient
PATIENT_PID=3

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial state for comparison
INITIAL_STATE=$(cat /tmp/initial_allergy_state.txt 2>/dev/null || echo "")
INITIAL_ALLERGY_COUNT=$(cat /tmp/initial_allergy_count.txt 2>/dev/null || echo "0")

# Parse initial state
INITIAL_ALLERGY_ID=""
INITIAL_SEVERITY=""
INITIAL_REACTION=""
INITIAL_MOD_TS=""

if [ -n "$INITIAL_STATE" ]; then
    INITIAL_ALLERGY_ID=$(echo "$INITIAL_STATE" | cut -f1)
    INITIAL_SEVERITY=$(echo "$INITIAL_STATE" | cut -f3)
    INITIAL_REACTION=$(echo "$INITIAL_STATE" | cut -f4)
    INITIAL_MOD_TS=$(echo "$INITIAL_STATE" | cut -f5)
fi

echo "Initial state:"
echo "  Allergy ID: $INITIAL_ALLERGY_ID"
echo "  Severity: $INITIAL_SEVERITY"
echo "  Reaction: $INITIAL_REACTION"
echo "  Modify timestamp: $INITIAL_MOD_TS"

# Get current allergy count (to detect if agent created duplicate)
CURRENT_ALLERGY_COUNT=$(openemr_query "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND type='allergy'" 2>/dev/null || echo "0")
echo "Allergy count: initial=$INITIAL_ALLERGY_COUNT, current=$CURRENT_ALLERGY_COUNT"

# Query current state of the penicillin allergy
echo ""
echo "=== Querying current allergy state ==="
CURRENT_ALLERGY=$(openemr_query "SELECT id, title, severity_al, reaction, UNIX_TIMESTAMP(modifydate) as mod_ts FROM lists WHERE pid=$PATIENT_PID AND type='allergy' AND (LOWER(title) LIKE '%penicillin%') ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Also get all allergies for debug
echo "All allergies for patient:"
openemr_query "SELECT id, title, severity_al, reaction FROM lists WHERE pid=$PATIENT_PID AND type='allergy'" 2>/dev/null

# Parse current allergy data
ALLERGY_FOUND="false"
CURRENT_ALLERGY_ID=""
CURRENT_TITLE=""
CURRENT_SEVERITY=""
CURRENT_REACTION=""
CURRENT_MOD_TS=""

if [ -n "$CURRENT_ALLERGY" ]; then
    ALLERGY_FOUND="true"
    CURRENT_ALLERGY_ID=$(echo "$CURRENT_ALLERGY" | cut -f1)
    CURRENT_TITLE=$(echo "$CURRENT_ALLERGY" | cut -f2)
    CURRENT_SEVERITY=$(echo "$CURRENT_ALLERGY" | cut -f3)
    CURRENT_REACTION=$(echo "$CURRENT_ALLERGY" | cut -f4)
    CURRENT_MOD_TS=$(echo "$CURRENT_ALLERGY" | cut -f5)
    
    echo ""
    echo "Current allergy state:"
    echo "  Allergy ID: $CURRENT_ALLERGY_ID"
    echo "  Title: $CURRENT_TITLE"
    echo "  Severity: $CURRENT_SEVERITY"
    echo "  Reaction: $CURRENT_REACTION"
    echo "  Modify timestamp: $CURRENT_MOD_TS"
fi

# Check if same record was edited (not duplicated)
SAME_RECORD="false"
if [ "$CURRENT_ALLERGY_ID" = "$INITIAL_ALLERGY_ID" ] && [ -n "$INITIAL_ALLERGY_ID" ]; then
    SAME_RECORD="true"
    echo "Same record confirmed (ID: $CURRENT_ALLERGY_ID)"
fi

# Check if record was modified during task
RECORD_MODIFIED="false"
if [ -n "$CURRENT_MOD_TS" ] && [ -n "$TASK_START" ]; then
    if [ "$CURRENT_MOD_TS" -gt "$TASK_START" ]; then
        RECORD_MODIFIED="true"
        echo "Record was modified during task"
    else
        echo "Record was NOT modified during task (mod_ts=$CURRENT_MOD_TS, task_start=$TASK_START)"
    fi
fi

# Check if severity was updated to severe
SEVERITY_UPDATED="false"
CURRENT_SEVERITY_LOWER=$(echo "$CURRENT_SEVERITY" | tr '[:upper:]' '[:lower:]')
if echo "$CURRENT_SEVERITY_LOWER" | grep -qi "severe"; then
    SEVERITY_UPDATED="true"
    echo "Severity updated to: $CURRENT_SEVERITY"
else
    echo "Severity NOT updated (current: $CURRENT_SEVERITY)"
fi

# Check if reaction includes anaphylaxis
REACTION_UPDATED="false"
CURRENT_REACTION_LOWER=$(echo "$CURRENT_REACTION" | tr '[:upper:]' '[:lower:]')
if echo "$CURRENT_REACTION_LOWER" | grep -qi "anaphylaxis"; then
    REACTION_UPDATED="true"
    echo "Reaction updated to include anaphylaxis: $CURRENT_REACTION"
else
    echo "Reaction does NOT include anaphylaxis (current: $CURRENT_REACTION)"
fi

# Check if duplicate was created
DUPLICATE_CREATED="false"
if [ "$CURRENT_ALLERGY_COUNT" -gt "$INITIAL_ALLERGY_COUNT" ]; then
    DUPLICATE_CREATED="true"
    echo "WARNING: New allergy record(s) created (duplicate detected)"
fi

# Escape special characters for JSON
CURRENT_TITLE_ESCAPED=$(echo "$CURRENT_TITLE" | sed 's/"/\\"/g' | tr '\n' ' ')
CURRENT_REACTION_ESCAPED=$(echo "$CURRENT_REACTION" | sed 's/"/\\"/g' | tr '\n' ' ')
INITIAL_REACTION_ESCAPED=$(echo "$INITIAL_REACTION" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/allergy_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": ${TASK_START:-0},
    "task_end_timestamp": ${TASK_END:-0},
    "initial_state": {
        "allergy_id": "$INITIAL_ALLERGY_ID",
        "severity": "$INITIAL_SEVERITY",
        "reaction": "$INITIAL_REACTION_ESCAPED",
        "modify_timestamp": "${INITIAL_MOD_TS:-0}",
        "allergy_count": ${INITIAL_ALLERGY_COUNT:-0}
    },
    "current_state": {
        "allergy_found": $ALLERGY_FOUND,
        "allergy_id": "$CURRENT_ALLERGY_ID",
        "title": "$CURRENT_TITLE_ESCAPED",
        "severity": "$CURRENT_SEVERITY",
        "reaction": "$CURRENT_REACTION_ESCAPED",
        "modify_timestamp": "${CURRENT_MOD_TS:-0}",
        "allergy_count": ${CURRENT_ALLERGY_COUNT:-0}
    },
    "validation": {
        "same_record_edited": $SAME_RECORD,
        "record_modified_during_task": $RECORD_MODIFIED,
        "severity_updated_to_severe": $SEVERITY_UPDATED,
        "reaction_includes_anaphylaxis": $REACTION_UPDATED,
        "duplicate_created": $DUPLICATE_CREATED
    },
    "screenshots": {
        "initial": "/tmp/task_initial_state.png",
        "final": "/tmp/task_final_state.png"
    }
}
EOF

# Save result
rm -f /tmp/update_allergy_result.json 2>/dev/null || sudo rm -f /tmp/update_allergy_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/update_allergy_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/update_allergy_result.json
chmod 666 /tmp/update_allergy_result.json 2>/dev/null || sudo chmod 666 /tmp/update_allergy_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/update_allergy_result.json"
cat /tmp/update_allergy_result.json

echo ""
echo "=== Export Complete ==="
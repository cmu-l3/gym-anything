#!/bin/bash
# Export script for Add Medical Problem Task

echo "=== Exporting Add Medical Problem Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Target patient
PATIENT_PID=3

# Get initial state recorded at setup
INITIAL_PROBLEM_COUNT=$(cat /tmp/initial_problem_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
PREEXISTING_OA=$(cat /tmp/preexisting_osteoarthritis 2>/dev/null || echo "")

echo "Initial problem count: $INITIAL_PROBLEM_COUNT"
echo "Task start timestamp: $TASK_START"

# Get current problem count for patient
CURRENT_PROBLEM_COUNT=$(openemr_query "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem'" 2>/dev/null || echo "0")
echo "Current problem count: $CURRENT_PROBLEM_COUNT"

# Debug: Show all current problems for this patient
echo ""
echo "=== DEBUG: All current problems for patient PID=$PATIENT_PID ==="
openemr_query "SELECT id, title, begdate, enddate, type, activity FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem' ORDER BY id DESC" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Query for osteoarthritis specifically (case-insensitive)
echo "Checking for osteoarthritis entry..."
OA_RECORD=$(openemr_query "SELECT id, title, begdate, enddate, type, activity, date FROM lists WHERE pid=$PATIENT_PID AND type='medical_problem' AND LOWER(title) LIKE '%osteoarthritis%' ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Parse the osteoarthritis record if found
OA_FOUND="false"
OA_ID=""
OA_TITLE=""
OA_BEGDATE=""
OA_ENDDATE=""
OA_TYPE=""
OA_ACTIVITY=""
OA_CREATED=""

if [ -n "$OA_RECORD" ]; then
    OA_FOUND="true"
    OA_ID=$(echo "$OA_RECORD" | cut -f1)
    OA_TITLE=$(echo "$OA_RECORD" | cut -f2)
    OA_BEGDATE=$(echo "$OA_RECORD" | cut -f3)
    OA_ENDDATE=$(echo "$OA_RECORD" | cut -f4)
    OA_TYPE=$(echo "$OA_RECORD" | cut -f5)
    OA_ACTIVITY=$(echo "$OA_RECORD" | cut -f6)
    OA_CREATED=$(echo "$OA_RECORD" | cut -f7)
    
    echo "Osteoarthritis record found:"
    echo "  ID: $OA_ID"
    echo "  Title: $OA_TITLE"
    echo "  Onset Date: $OA_BEGDATE"
    echo "  End Date: $OA_ENDDATE"
    echo "  Type: $OA_TYPE"
    echo "  Activity: $OA_ACTIVITY"
    echo "  Created: $OA_CREATED"
else
    echo "No osteoarthritis record found"
fi

# Check if this is a newly created record or pre-existing
IS_NEW_RECORD="false"
if [ -n "$OA_ID" ]; then
    # Check if this ID was in the pre-existing list
    EXISTING_IDS=$(cat /tmp/existing_problem_ids 2>/dev/null || echo "")
    if ! echo "$EXISTING_IDS" | grep -q "^${OA_ID}$"; then
        IS_NEW_RECORD="true"
        echo "Record ID $OA_ID is NEW (not in pre-existing list)"
    else
        echo "Record ID $OA_ID was PRE-EXISTING (potential gaming attempt)"
    fi
fi

# Validate onset date matches expected
DATE_MATCHES="false"
EXPECTED_DATE="2024-01-15"
if [ "$OA_BEGDATE" = "$EXPECTED_DATE" ]; then
    DATE_MATCHES="true"
    echo "Onset date matches expected: $EXPECTED_DATE"
else
    echo "Onset date mismatch: expected '$EXPECTED_DATE', got '$OA_BEGDATE'"
fi

# Check if problem is marked as active (no end date, activity=1)
IS_ACTIVE="false"
if [ -z "$OA_ENDDATE" ] || [ "$OA_ENDDATE" = "NULL" ] || [ "$OA_ENDDATE" = "0000-00-00" ]; then
    if [ "$OA_ACTIVITY" = "1" ] || [ -z "$OA_ACTIVITY" ]; then
        IS_ACTIVE="true"
        echo "Problem is active (no end date)"
    fi
fi

# Check if any new problem was added (even if not osteoarthritis)
ANY_NEW_PROBLEM="false"
if [ "$CURRENT_PROBLEM_COUNT" -gt "$INITIAL_PROBLEM_COUNT" ]; then
    ANY_NEW_PROBLEM="true"
    NEW_COUNT=$((CURRENT_PROBLEM_COUNT - INITIAL_PROBLEM_COUNT))
    echo "New problems added: $NEW_COUNT"
fi

# Escape special characters for JSON
OA_TITLE_ESCAPED=$(echo "$OA_TITLE" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/medical_problem_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "initial_problem_count": ${INITIAL_PROBLEM_COUNT:-0},
    "current_problem_count": ${CURRENT_PROBLEM_COUNT:-0},
    "any_new_problem_added": $ANY_NEW_PROBLEM,
    "osteoarthritis_found": $OA_FOUND,
    "is_new_record": $IS_NEW_RECORD,
    "preexisting_oa": $([ -n "$PREEXISTING_OA" ] && echo "true" || echo "false"),
    "problem": {
        "id": "$OA_ID",
        "title": "$OA_TITLE_ESCAPED",
        "onset_date": "$OA_BEGDATE",
        "end_date": "$OA_ENDDATE",
        "type": "$OA_TYPE",
        "activity": "$OA_ACTIVITY",
        "created_datetime": "$OA_CREATED"
    },
    "validation": {
        "date_matches_expected": $DATE_MATCHES,
        "is_active": $IS_ACTIVE,
        "expected_onset_date": "$EXPECTED_DATE"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final location
rm -f /tmp/medical_problem_result.json 2>/dev/null || sudo rm -f /tmp/medical_problem_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/medical_problem_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/medical_problem_result.json
chmod 666 /tmp/medical_problem_result.json 2>/dev/null || sudo chmod 666 /tmp/medical_problem_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/medical_problem_result.json"
cat /tmp/medical_problem_result.json

echo ""
echo "=== Export Complete ==="
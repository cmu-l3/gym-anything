#!/bin/bash
# Export script for Document Assessment and Plan Task

echo "=== Exporting Document Assessment and Plan Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot saved to /tmp/task_final.png"

# Target patient
PATIENT_PID=3

# Get initial counts
INITIAL_SOAP_COUNT=$(cat /tmp/initial_soap_count 2>/dev/null || echo "0")
INITIAL_ENCOUNTER_COUNT=$(cat /tmp/initial_encounter_count 2>/dev/null || echo "0")
INITIAL_FORMS_COUNT=$(cat /tmp/initial_forms_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

echo "Initial counts - SOAP: $INITIAL_SOAP_COUNT, Encounters: $INITIAL_ENCOUNTER_COUNT, Forms: $INITIAL_FORMS_COUNT"
echo "Task start timestamp: $TASK_START"

# Get current counts
CURRENT_SOAP_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_soap WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_ENCOUNTER_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_FORMS_COUNT=$(openemr_query "SELECT COUNT(*) FROM forms WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo "Current counts - SOAP: $CURRENT_SOAP_COUNT, Encounters: $CURRENT_ENCOUNTER_COUNT, Forms: $CURRENT_FORMS_COUNT"

# Check for new SOAP forms
echo ""
echo "=== Querying SOAP forms for patient PID=$PATIENT_PID ==="
SOAP_FORMS=$(openemr_query "SELECT id, date, pid, user, assessment, plan FROM form_soap WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "SOAP forms found:"
echo "$SOAP_FORMS"

# Get the most recent SOAP form with content
NEWEST_SOAP=$(openemr_query "SELECT id, date, pid, user, assessment, plan FROM form_soap WHERE pid=$PATIENT_PID AND (assessment IS NOT NULL AND assessment != '' OR plan IS NOT NULL AND plan != '') ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Parse SOAP form data
SOAP_FOUND="false"
SOAP_ID=""
SOAP_DATE=""
SOAP_USER=""
SOAP_ASSESSMENT=""
SOAP_PLAN=""

if [ -n "$NEWEST_SOAP" ]; then
    SOAP_FOUND="true"
    SOAP_ID=$(echo "$NEWEST_SOAP" | cut -f1)
    SOAP_DATE=$(echo "$NEWEST_SOAP" | cut -f2)
    SOAP_PID=$(echo "$NEWEST_SOAP" | cut -f3)
    SOAP_USER=$(echo "$NEWEST_SOAP" | cut -f4)
    SOAP_ASSESSMENT=$(echo "$NEWEST_SOAP" | cut -f5)
    SOAP_PLAN=$(echo "$NEWEST_SOAP" | cut -f6)
    
    echo ""
    echo "Most recent SOAP form with content:"
    echo "  ID: $SOAP_ID"
    echo "  Date: $SOAP_DATE"
    echo "  User: $SOAP_USER"
    echo "  Assessment: $SOAP_ASSESSMENT"
    echo "  Plan: $SOAP_PLAN"
fi

# Check for new encounters
echo ""
echo "=== Querying encounters for patient PID=$PATIENT_PID ==="
ENCOUNTERS=$(openemr_query "SELECT id, date, reason, pid FROM form_encounter WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "Encounters found:"
echo "$ENCOUNTERS"

NEWEST_ENCOUNTER=$(openemr_query "SELECT id, date, reason FROM form_encounter WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
ENCOUNTER_ID=""
ENCOUNTER_DATE=""
ENCOUNTER_REASON=""

if [ -n "$NEWEST_ENCOUNTER" ]; then
    ENCOUNTER_ID=$(echo "$NEWEST_ENCOUNTER" | cut -f1)
    ENCOUNTER_DATE=$(echo "$NEWEST_ENCOUNTER" | cut -f2)
    ENCOUNTER_REASON=$(echo "$NEWEST_ENCOUNTER" | cut -f3)
    echo ""
    echo "Most recent encounter: ID=$ENCOUNTER_ID, Date=$ENCOUNTER_DATE, Reason=$ENCOUNTER_REASON"
fi

# Check if SOAP was newly created (count increased)
NEW_SOAP_CREATED="false"
if [ "$CURRENT_SOAP_COUNT" -gt "$INITIAL_SOAP_COUNT" ]; then
    NEW_SOAP_CREATED="true"
    echo "New SOAP form detected (count: $INITIAL_SOAP_COUNT -> $CURRENT_SOAP_COUNT)"
fi

# Check if encounter was newly created
NEW_ENCOUNTER_CREATED="false"
if [ "$CURRENT_ENCOUNTER_COUNT" -gt "$INITIAL_ENCOUNTER_COUNT" ]; then
    NEW_ENCOUNTER_CREATED="true"
    echo "New encounter detected (count: $INITIAL_ENCOUNTER_COUNT -> $CURRENT_ENCOUNTER_COUNT)"
fi

# Validate assessment contains hypertension-related keywords
ASSESSMENT_VALID="false"
ASSESSMENT_LOWER=$(echo "$SOAP_ASSESSMENT" | tr '[:upper:]' '[:lower:]')
if echo "$ASSESSMENT_LOWER" | grep -qE "(hypertension|htn|blood pressure|bp|controlled|well.controlled)"; then
    ASSESSMENT_VALID="true"
    echo "Assessment contains hypertension-related keywords"
else
    echo "Assessment does NOT contain expected keywords"
fi

# Validate plan contains required elements
PLAN_VALID="false"
PLAN_LOWER=$(echo "$SOAP_PLAN" | tr '[:upper:]' '[:lower:]')
if echo "$PLAN_LOWER" | grep -qE "(continue|medication|follow.?up|return|lifestyle|diet|exercise|recheck)"; then
    PLAN_VALID="true"
    echo "Plan contains required treatment plan keywords"
else
    echo "Plan does NOT contain expected keywords"
fi

# Check if assessment has any content
ASSESSMENT_HAS_CONTENT="false"
if [ -n "$SOAP_ASSESSMENT" ] && [ ${#SOAP_ASSESSMENT} -gt 10 ]; then
    ASSESSMENT_HAS_CONTENT="true"
fi

# Check if plan has any content
PLAN_HAS_CONTENT="false"
if [ -n "$SOAP_PLAN" ] && [ ${#SOAP_PLAN} -gt 10 ]; then
    PLAN_HAS_CONTENT="true"
fi

# Escape special characters for JSON
SOAP_ASSESSMENT_ESCAPED=$(echo "$SOAP_ASSESSMENT" | sed 's/"/\\"/g' | tr '\n' ' ' | cut -c1-500)
SOAP_PLAN_ESCAPED=$(echo "$SOAP_PLAN" | sed 's/"/\\"/g' | tr '\n' ' ' | cut -c1-500)
ENCOUNTER_REASON_ESCAPED=$(echo "$ENCOUNTER_REASON" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/assessment_plan_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "initial_counts": {
        "soap": ${INITIAL_SOAP_COUNT:-0},
        "encounter": ${INITIAL_ENCOUNTER_COUNT:-0},
        "forms": ${INITIAL_FORMS_COUNT:-0}
    },
    "current_counts": {
        "soap": ${CURRENT_SOAP_COUNT:-0},
        "encounter": ${CURRENT_ENCOUNTER_COUNT:-0},
        "forms": ${CURRENT_FORMS_COUNT:-0}
    },
    "soap_form": {
        "found": $SOAP_FOUND,
        "id": "$SOAP_ID",
        "date": "$SOAP_DATE",
        "user": "$SOAP_USER",
        "assessment": "$SOAP_ASSESSMENT_ESCAPED",
        "plan": "$SOAP_PLAN_ESCAPED"
    },
    "encounter": {
        "id": "$ENCOUNTER_ID",
        "date": "$ENCOUNTER_DATE",
        "reason": "$ENCOUNTER_REASON_ESCAPED"
    },
    "validation": {
        "new_soap_created": $NEW_SOAP_CREATED,
        "new_encounter_created": $NEW_ENCOUNTER_CREATED,
        "assessment_has_content": $ASSESSMENT_HAS_CONTENT,
        "assessment_keywords_valid": $ASSESSMENT_VALID,
        "plan_has_content": $PLAN_HAS_CONTENT,
        "plan_keywords_valid": $PLAN_VALID
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/assessment_plan_result.json 2>/dev/null || sudo rm -f /tmp/assessment_plan_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/assessment_plan_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/assessment_plan_result.json
chmod 666 /tmp/assessment_plan_result.json 2>/dev/null || sudo chmod 666 /tmp/assessment_plan_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/assessment_plan_result.json"
cat /tmp/assessment_plan_result.json
echo ""
echo "=== Export Complete ==="
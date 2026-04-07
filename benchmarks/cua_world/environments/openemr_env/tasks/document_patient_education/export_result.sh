#!/bin/bash
# Export script for Document Patient Education Task

echo "=== Exporting Document Patient Education Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=5
PATIENT_FNAME="Jacinto"
PATIENT_LNAME="Kiehn"

# Get task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Task duration: $TASK_START to $TASK_END"

# Take final screenshot
take_screenshot /tmp/task_final_state.png
echo "Final screenshot saved"

# Get initial counts
INITIAL_FORM_COUNT=$(cat /tmp/initial_form_count.txt 2>/dev/null || echo "0")
INITIAL_PNOTES_COUNT=$(cat /tmp/initial_pnotes_count.txt 2>/dev/null || echo "0")
INITIAL_ENCOUNTER_COUNT=$(cat /tmp/initial_encounter_count.txt 2>/dev/null || echo "0")
LATEST_FORM_ID=$(cat /tmp/latest_form_id.txt 2>/dev/null || echo "0")
LATEST_PNOTES_ID=$(cat /tmp/latest_pnotes_id.txt 2>/dev/null || echo "0")
LATEST_ENCOUNTER_ID=$(cat /tmp/latest_encounter_id.txt 2>/dev/null || echo "0")

# Get current counts
CURRENT_FORM_COUNT=$(openemr_query "SELECT COUNT(*) FROM forms WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_PNOTES_COUNT=$(openemr_query "SELECT COUNT(*) FROM pnotes WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_ENCOUNTER_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo ""
echo "=== State Comparison ==="
echo "Forms: $INITIAL_FORM_COUNT -> $CURRENT_FORM_COUNT"
echo "Patient Notes: $INITIAL_PNOTES_COUNT -> $CURRENT_PNOTES_COUNT"
echo "Encounters: $INITIAL_ENCOUNTER_COUNT -> $CURRENT_ENCOUNTER_COUNT"

# Check for new forms (any form added to this patient)
echo ""
echo "=== Checking for new forms ==="
NEW_FORMS=$(openemr_query "SELECT id, date, form_name, formdir FROM forms WHERE pid=$PATIENT_PID AND id > $LATEST_FORM_ID ORDER BY id DESC LIMIT 5" 2>/dev/null)
if [ -n "$NEW_FORMS" ]; then
    echo "New forms found:"
    echo "$NEW_FORMS"
else
    echo "No new forms found"
fi

# Check for new patient notes
echo ""
echo "=== Checking for new patient notes ==="
NEW_PNOTES=$(openemr_query "SELECT id, date, title, body FROM pnotes WHERE pid=$PATIENT_PID AND id > $LATEST_PNOTES_ID ORDER BY id DESC LIMIT 5" 2>/dev/null)
if [ -n "$NEW_PNOTES" ]; then
    echo "New patient notes found:"
    echo "$NEW_PNOTES"
else
    echo "No new patient notes found"
fi

# Check for new encounters
echo ""
echo "=== Checking for new encounters ==="
NEW_ENCOUNTERS=$(openemr_query "SELECT id, date, reason FROM form_encounter WHERE pid=$PATIENT_PID AND id > $LATEST_ENCOUNTER_ID ORDER BY id DESC LIMIT 5" 2>/dev/null)
if [ -n "$NEW_ENCOUNTERS" ]; then
    echo "New encounters found:"
    echo "$NEW_ENCOUNTERS"
else
    echo "No new encounters found"
fi

# Search for education-related content in forms (check form_vitals, soap notes, etc.)
echo ""
echo "=== Searching for education keywords in recent documentation ==="

# Check pnotes for education keywords
EDUCATION_IN_PNOTES=$(openemr_query "SELECT id, date, title, body FROM pnotes WHERE pid=$PATIENT_PID AND id > $LATEST_PNOTES_ID AND (LOWER(body) LIKE '%diet%' OR LOWER(body) LIKE '%education%' OR LOWER(body) LIKE '%counsel%' OR LOWER(body) LIKE '%diabetes%' OR LOWER(body) LIKE '%nutrition%' OR LOWER(body) LIKE '%carbohydrate%') ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Check form_encounter reason field
EDUCATION_IN_ENCOUNTER=$(openemr_query "SELECT id, date, reason FROM form_encounter WHERE pid=$PATIENT_PID AND id > $LATEST_ENCOUNTER_ID AND (LOWER(reason) LIKE '%diet%' OR LOWER(reason) LIKE '%education%' OR LOWER(reason) LIKE '%counsel%' OR LOWER(reason) LIKE '%diabetes%') ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Get the most recent new note content for analysis
NEWEST_PNOTE_CONTENT=""
NEWEST_PNOTE_ID=""
if [ -n "$NEW_PNOTES" ]; then
    NEWEST_PNOTE_ID=$(echo "$NEW_PNOTES" | head -1 | cut -f1)
    NEWEST_PNOTE_CONTENT=$(openemr_query "SELECT body FROM pnotes WHERE id=$NEWEST_PNOTE_ID" 2>/dev/null)
fi

# Get most recent new encounter info
NEWEST_ENCOUNTER_ID=""
NEWEST_ENCOUNTER_REASON=""
if [ -n "$NEW_ENCOUNTERS" ]; then
    NEWEST_ENCOUNTER_ID=$(echo "$NEW_ENCOUNTERS" | head -1 | cut -f1)
    NEWEST_ENCOUNTER_REASON=$(openemr_query "SELECT reason FROM form_encounter WHERE id=$NEWEST_ENCOUNTER_ID" 2>/dev/null)
fi

# Determine if documentation was found
DOCUMENTATION_FOUND="false"
DOCUMENTATION_TYPE=""
DOCUMENTATION_CONTENT=""

if [ -n "$EDUCATION_IN_PNOTES" ]; then
    DOCUMENTATION_FOUND="true"
    DOCUMENTATION_TYPE="patient_note"
    DOCUMENTATION_CONTENT=$(echo "$EDUCATION_IN_PNOTES" | cut -f4)
    echo "Education documentation found in patient notes"
elif [ -n "$EDUCATION_IN_ENCOUNTER" ]; then
    DOCUMENTATION_FOUND="true"
    DOCUMENTATION_TYPE="encounter_reason"
    DOCUMENTATION_CONTENT=$(echo "$EDUCATION_IN_ENCOUNTER" | cut -f3)
    echo "Education documentation found in encounter reason"
elif [ -n "$NEWEST_PNOTE_CONTENT" ]; then
    # Check if newest note has any relevant content
    CONTENT_LOWER=$(echo "$NEWEST_PNOTE_CONTENT" | tr '[:upper:]' '[:lower:]')
    if echo "$CONTENT_LOWER" | grep -qE "(diet|education|counsel|diabetes|nutrition|carbohydrate|glucose|glycemic)"; then
        DOCUMENTATION_FOUND="true"
        DOCUMENTATION_TYPE="patient_note"
        DOCUMENTATION_CONTENT="$NEWEST_PNOTE_CONTENT"
        echo "Education documentation found in newest patient note"
    fi
fi

# Check if any new documentation exists even without keywords
NEW_DOCUMENTATION_EXISTS="false"
if [ "$CURRENT_FORM_COUNT" -gt "$INITIAL_FORM_COUNT" ] || [ "$CURRENT_PNOTES_COUNT" -gt "$INITIAL_PNOTES_COUNT" ]; then
    NEW_DOCUMENTATION_EXISTS="true"
fi

# Check for encounter created
ENCOUNTER_CREATED="false"
if [ "$CURRENT_ENCOUNTER_COUNT" -gt "$INITIAL_ENCOUNTER_COUNT" ]; then
    ENCOUNTER_CREATED="true"
fi

# Escape content for JSON
DOCUMENTATION_CONTENT_ESCAPED=$(echo "$DOCUMENTATION_CONTENT" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)
NEWEST_PNOTE_CONTENT_ESCAPED=$(echo "$NEWEST_PNOTE_CONTENT" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)
NEWEST_ENCOUNTER_REASON_ESCAPED=$(echo "$NEWEST_ENCOUNTER_REASON" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 200)

# Create result JSON
TEMP_JSON=$(mktemp /tmp/education_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "patient_name": "$PATIENT_FNAME $PATIENT_LNAME",
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_counts": {
        "forms": ${INITIAL_FORM_COUNT:-0},
        "pnotes": ${INITIAL_PNOTES_COUNT:-0},
        "encounters": ${INITIAL_ENCOUNTER_COUNT:-0}
    },
    "current_counts": {
        "forms": ${CURRENT_FORM_COUNT:-0},
        "pnotes": ${CURRENT_PNOTES_COUNT:-0},
        "encounters": ${CURRENT_ENCOUNTER_COUNT:-0}
    },
    "latest_ids_before_task": {
        "form_id": ${LATEST_FORM_ID:-0},
        "pnotes_id": ${LATEST_PNOTES_ID:-0},
        "encounter_id": ${LATEST_ENCOUNTER_ID:-0}
    },
    "new_documentation_exists": $NEW_DOCUMENTATION_EXISTS,
    "encounter_created": $ENCOUNTER_CREATED,
    "education_documentation_found": $DOCUMENTATION_FOUND,
    "documentation_type": "$DOCUMENTATION_TYPE",
    "documentation_content": "$DOCUMENTATION_CONTENT_ESCAPED",
    "newest_pnote_id": "$NEWEST_PNOTE_ID",
    "newest_pnote_content": "$NEWEST_PNOTE_CONTENT_ESCAPED",
    "newest_encounter_id": "$NEWEST_ENCOUNTER_ID",
    "newest_encounter_reason": "$NEWEST_ENCOUNTER_REASON_ESCAPED",
    "screenshot_path": "/tmp/task_final_state.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/patient_education_result.json 2>/dev/null || sudo rm -f /tmp/patient_education_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/patient_education_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/patient_education_result.json
chmod 666 /tmp/patient_education_result.json 2>/dev/null || sudo chmod 666 /tmp/patient_education_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Summary ==="
echo "Documentation found: $DOCUMENTATION_FOUND"
echo "Documentation type: $DOCUMENTATION_TYPE"
echo "New documentation exists: $NEW_DOCUMENTATION_EXISTS"
echo "Encounter created: $ENCOUNTER_CREATED"
echo ""
echo "Result saved to /tmp/patient_education_result.json"
cat /tmp/patient_education_result.json
echo ""
echo "=== Export Complete ==="
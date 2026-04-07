#!/bin/bash
# Export script for Document PHQ-9 Screening Task

echo "=== Exporting PHQ-9 Screening Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Target patient
PATIENT_PID=3

# Get initial counts and timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_NOTES_COUNT=$(cat /tmp/initial_notes_count 2>/dev/null || echo "0")
INITIAL_FORMS_COUNT=$(cat /tmp/initial_forms_count 2>/dev/null || echo "0")
INITIAL_ENCOUNTERS_COUNT=$(cat /tmp/initial_encounters_count 2>/dev/null || echo "0")

echo "Task start timestamp: $TASK_START"
echo "Initial counts: notes=$INITIAL_NOTES_COUNT, forms=$INITIAL_FORMS_COUNT, encounters=$INITIAL_ENCOUNTERS_COUNT"

# Get current counts
CURRENT_NOTES_COUNT=$(openemr_query "SELECT COUNT(*) FROM pnotes WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_FORMS_COUNT=$(openemr_query "SELECT COUNT(*) FROM forms f JOIN form_encounter fe ON f.encounter = fe.encounter WHERE fe.pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_ENCOUNTERS_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo "Current counts: notes=$CURRENT_NOTES_COUNT, forms=$CURRENT_FORMS_COUNT, encounters=$CURRENT_ENCOUNTERS_COUNT"

# Search for PHQ-9 documentation in various locations

# METHOD 1: Check patient notes (pnotes table) for PHQ-9 related content
echo ""
echo "=== Searching for PHQ-9 in patient notes ==="
PHQ_NOTES=$(openemr_query "SELECT id, date, user, title, body FROM pnotes WHERE pid=$PATIENT_PID AND (LOWER(body) LIKE '%phq%' OR LOWER(body) LIKE '%depression%screening%' OR LOWER(body) LIKE '%score%8%' OR LOWER(title) LIKE '%phq%' OR LOWER(title) LIKE '%depression%') ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "PHQ-related notes found:"
echo "$PHQ_NOTES"

# Check if any notes mention score of 8 or mild depression
PHQ_SCORE_8_FOUND="false"
PHQ_MILD_FOUND="false"
PHQ_NOTE_ID=""
PHQ_NOTE_DATE=""
PHQ_NOTE_BODY=""

if [ -n "$PHQ_NOTES" ]; then
    # Get the most recent note that mentions PHQ or depression
    PHQ_NOTE_ID=$(echo "$PHQ_NOTES" | head -1 | cut -f1)
    PHQ_NOTE_DATE=$(echo "$PHQ_NOTES" | head -1 | cut -f2)
    PHQ_NOTE_BODY=$(echo "$PHQ_NOTES" | head -1 | cut -f5)
    
    # Check for score of 8
    if echo "$PHQ_NOTES" | grep -qiE "(score.*8|8.*score|phq.*8|8.*phq|\b8\b.*point|\b8\b.*mild)"; then
        PHQ_SCORE_8_FOUND="true"
        echo "Score of 8 found in notes"
    fi
    
    # Check for mild interpretation
    if echo "$PHQ_NOTES" | grep -qi "mild"; then
        PHQ_MILD_FOUND="true"
        echo "Mild interpretation found in notes"
    fi
fi

# METHOD 2: Check forms table for PHQ-9 forms
echo ""
echo "=== Searching for PHQ-9 forms ==="
PHQ_FORMS=$(openemr_query "SELECT f.id, f.date, f.form_name, f.formdir FROM forms f JOIN form_encounter fe ON f.encounter = fe.encounter WHERE fe.pid=$PATIENT_PID AND (LOWER(f.form_name) LIKE '%phq%' OR LOWER(f.form_name) LIKE '%depression%' OR LOWER(f.formdir) LIKE '%phq%') ORDER BY f.id DESC LIMIT 5" 2>/dev/null)
echo "PHQ-related forms found:"
echo "$PHQ_FORMS"

PHQ_FORM_FOUND="false"
PHQ_FORM_ID=""
PHQ_FORM_DATE=""
if [ -n "$PHQ_FORMS" ]; then
    PHQ_FORM_FOUND="true"
    PHQ_FORM_ID=$(echo "$PHQ_FORMS" | head -1 | cut -f1)
    PHQ_FORM_DATE=$(echo "$PHQ_FORMS" | head -1 | cut -f2)
fi

# METHOD 3: Check layout-based forms (lbf_data)
echo ""
echo "=== Searching for PHQ-9 in LBF forms ==="
LBF_PHQ=$(openemr_query "SELECT DISTINCT ld.form_id, f.form_name, ld.field_id, ld.field_value FROM lbf_data ld JOIN forms f ON ld.form_id = f.id WHERE f.pid=$PATIENT_PID AND (LOWER(ld.field_id) LIKE '%phq%' OR LOWER(ld.field_value) LIKE '%phq%' OR LOWER(ld.field_value) LIKE '%depression%') ORDER BY ld.form_id DESC LIMIT 10" 2>/dev/null)
echo "LBF PHQ data:"
echo "$LBF_PHQ"

LBF_FOUND="false"
if [ -n "$LBF_PHQ" ]; then
    LBF_FOUND="true"
fi

# METHOD 4: Check SOAP notes and encounter forms
echo ""
echo "=== Searching in SOAP/encounter notes ==="
SOAP_PHQ=$(openemr_query "SELECT id, date, subjective, objective, assessment FROM form_soap WHERE id IN (SELECT form_id FROM forms WHERE formdir='soap' AND pid=$PATIENT_PID) AND (LOWER(subjective) LIKE '%phq%' OR LOWER(assessment) LIKE '%phq%' OR LOWER(assessment) LIKE '%depression%' OR LOWER(subjective) LIKE '%depression%') ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "SOAP notes with PHQ:"
echo "$SOAP_PHQ"

SOAP_FOUND="false"
if [ -n "$SOAP_PHQ" ]; then
    SOAP_FOUND="true"
    # Check for score 8 in SOAP
    if echo "$SOAP_PHQ" | grep -qiE "(score.*8|8.*score|\b8\b)"; then
        PHQ_SCORE_8_FOUND="true"
    fi
    if echo "$SOAP_PHQ" | grep -qi "mild"; then
        PHQ_MILD_FOUND="true"
    fi
fi

# METHOD 5: Check clinical notes (form_clinical_notes)
echo ""
echo "=== Searching clinical notes ==="
CLINICAL_NOTES=$(openemr_query "SELECT id, date, description, clinical_notes_type FROM form_clinical_notes WHERE id IN (SELECT form_id FROM forms f JOIN form_encounter fe ON f.encounter = fe.encounter WHERE fe.pid=$PATIENT_PID AND f.formdir='clinical_notes') AND (LOWER(description) LIKE '%phq%' OR LOWER(description) LIKE '%depression%') ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "Clinical notes:"
echo "$CLINICAL_NOTES"

CLINICAL_FOUND="false"
if [ -n "$CLINICAL_NOTES" ]; then
    CLINICAL_FOUND="true"
fi

# Determine if documentation was created during task
DOCUMENTATION_FOUND="false"
DOCUMENTATION_TYPE=""
NEWLY_CREATED="false"

if [ "$PHQ_NOTES" != "" ] || [ "$PHQ_FORM_FOUND" = "true" ] || [ "$LBF_FOUND" = "true" ] || [ "$SOAP_FOUND" = "true" ] || [ "$CLINICAL_FOUND" = "true" ]; then
    DOCUMENTATION_FOUND="true"
    
    # Determine primary documentation type
    if [ "$PHQ_FORM_FOUND" = "true" ]; then
        DOCUMENTATION_TYPE="form"
    elif [ "$SOAP_FOUND" = "true" ]; then
        DOCUMENTATION_TYPE="soap"
    elif [ "$CLINICAL_FOUND" = "true" ]; then
        DOCUMENTATION_TYPE="clinical_notes"
    elif [ -n "$PHQ_NOTES" ]; then
        DOCUMENTATION_TYPE="patient_note"
    elif [ "$LBF_FOUND" = "true" ]; then
        DOCUMENTATION_TYPE="lbf_form"
    fi
    
    # Check if newly created (count increased)
    if [ "$CURRENT_NOTES_COUNT" -gt "$INITIAL_NOTES_COUNT" ] || \
       [ "$CURRENT_FORMS_COUNT" -gt "$INITIAL_FORMS_COUNT" ] || \
       [ "$CURRENT_ENCOUNTERS_COUNT" -gt "$INITIAL_ENCOUNTERS_COUNT" ]; then
        NEWLY_CREATED="true"
    fi
fi

# Additional check: Search all recent entries containing "8" and PHQ/depression keywords
echo ""
echo "=== Final verification search ==="
FINAL_CHECK=$(openemr_query "SELECT 'pnotes' as source, id, date, body as content FROM pnotes WHERE pid=$PATIENT_PID AND date >= DATE_SUB(NOW(), INTERVAL 1 HOUR) UNION ALL SELECT 'forms' as source, f.id, f.date, f.form_name as content FROM forms f JOIN form_encounter fe ON f.encounter = fe.encounter WHERE fe.pid=$PATIENT_PID AND f.date >= DATE_SUB(NOW(), INTERVAL 1 HOUR) ORDER BY date DESC LIMIT 10" 2>/dev/null)
echo "Recent entries (last hour):"
echo "$FINAL_CHECK"

# Check if recent entries mention PHQ/depression/8
if echo "$FINAL_CHECK" | grep -qiE "(phq|depression|screening)"; then
    DOCUMENTATION_FOUND="true"
    NEWLY_CREATED="true"
fi

# Escape special characters for JSON
PHQ_NOTE_BODY_ESCAPED=$(echo "$PHQ_NOTE_BODY" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)

# Create result JSON
TEMP_JSON=$(mktemp /tmp/phq9_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "initial_counts": {
        "notes": ${INITIAL_NOTES_COUNT:-0},
        "forms": ${INITIAL_FORMS_COUNT:-0},
        "encounters": ${INITIAL_ENCOUNTERS_COUNT:-0}
    },
    "current_counts": {
        "notes": ${CURRENT_NOTES_COUNT:-0},
        "forms": ${CURRENT_FORMS_COUNT:-0},
        "encounters": ${CURRENT_ENCOUNTERS_COUNT:-0}
    },
    "documentation_found": $DOCUMENTATION_FOUND,
    "documentation_type": "$DOCUMENTATION_TYPE",
    "newly_created": $NEWLY_CREATED,
    "phq_data": {
        "score_8_found": $PHQ_SCORE_8_FOUND,
        "mild_interpretation_found": $PHQ_MILD_FOUND,
        "note_id": "$PHQ_NOTE_ID",
        "note_date": "$PHQ_NOTE_DATE",
        "form_found": $PHQ_FORM_FOUND,
        "form_id": "$PHQ_FORM_ID",
        "lbf_found": $LBF_FOUND,
        "soap_found": $SOAP_FOUND,
        "clinical_notes_found": $CLINICAL_FOUND
    },
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/phq9_screening_result.json 2>/dev/null || sudo rm -f /tmp/phq9_screening_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/phq9_screening_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/phq9_screening_result.json
chmod 666 /tmp/phq9_screening_result.json 2>/dev/null || sudo chmod 666 /tmp/phq9_screening_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/phq9_screening_result.json"
cat /tmp/phq9_screening_result.json

echo ""
echo "=== Export Complete ==="
#!/bin/bash
# Export script for Document Tobacco Cessation Counseling Task

echo "=== Exporting Tobacco Counseling Documentation Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot saved to /tmp/task_final.png"

# Target patient
PATIENT_PID=2

# Get task timing
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
TASK_DATE=$(cat /tmp/task_date 2>/dev/null || date +%Y-%m-%d)

# Get initial counts
INITIAL_ENCOUNTER_COUNT=$(cat /tmp/initial_encounter_count 2>/dev/null || echo "0")
INITIAL_FORMS_COUNT=$(cat /tmp/initial_forms_count 2>/dev/null || echo "0")
LAST_FORM_ID=$(cat /tmp/last_form_id 2>/dev/null || echo "0")
LAST_ENCOUNTER_ID=$(cat /tmp/last_encounter_id 2>/dev/null || echo "0")

# Get current counts
CURRENT_ENCOUNTER_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_FORMS_COUNT=$(openemr_query "SELECT COUNT(*) FROM forms WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo "Encounter count: initial=$INITIAL_ENCOUNTER_COUNT, current=$CURRENT_ENCOUNTER_COUNT"
echo "Forms count: initial=$INITIAL_FORMS_COUNT, current=$CURRENT_FORMS_COUNT"

# Check for encounters created today for this patient
echo ""
echo "=== Checking encounters for patient PID=$PATIENT_PID ==="
TODAY_ENCOUNTERS=$(openemr_query "SELECT id, date, reason, encounter FROM form_encounter WHERE pid=$PATIENT_PID AND DATE(date)='$TASK_DATE' ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "Today's encounters:"
echo "$TODAY_ENCOUNTERS"

# Check for new encounters (id > last_encounter_id)
NEW_ENCOUNTER=$(openemr_query "SELECT id, date, reason, encounter FROM form_encounter WHERE pid=$PATIENT_PID AND id > $LAST_ENCOUNTER_ID ORDER BY id DESC LIMIT 1" 2>/dev/null)

ENCOUNTER_FOUND="false"
ENCOUNTER_ID=""
ENCOUNTER_DATE=""
ENCOUNTER_REASON=""
ENCOUNTER_NUM=""

if [ -n "$NEW_ENCOUNTER" ]; then
    ENCOUNTER_FOUND="true"
    ENCOUNTER_ID=$(echo "$NEW_ENCOUNTER" | cut -f1)
    ENCOUNTER_DATE=$(echo "$NEW_ENCOUNTER" | cut -f2)
    ENCOUNTER_REASON=$(echo "$NEW_ENCOUNTER" | cut -f3)
    ENCOUNTER_NUM=$(echo "$NEW_ENCOUNTER" | cut -f4)
    echo "New encounter found: ID=$ENCOUNTER_ID, Date=$ENCOUNTER_DATE, Reason=$ENCOUNTER_REASON"
fi

# Check for forms containing tobacco-related content
echo ""
echo "=== Checking forms for tobacco-related content ==="

# Query forms table for new forms
NEW_FORMS=$(openemr_query "SELECT id, form_name, form_id, encounter FROM forms WHERE pid=$PATIENT_PID AND id > $LAST_FORM_ID ORDER BY id DESC" 2>/dev/null)
echo "New forms:"
echo "$NEW_FORMS"

# Search for tobacco-related content in various form tables
TOBACCO_FOUND="false"
TOBACCO_CONTENT=""

# Check form_clinical_notes for tobacco references
echo ""
echo "Checking clinical notes..."
CLINICAL_NOTES=$(openemr_query "SELECT cn.id, cn.description, cn.clinical_notes_type, f.date FROM form_clinical_notes cn JOIN forms f ON f.form_id = cn.id AND f.formdir = 'clinical_notes' WHERE f.pid=$PATIENT_PID AND f.id > $LAST_FORM_ID" 2>/dev/null)
if [ -n "$CLINICAL_NOTES" ]; then
    echo "Clinical notes found: $CLINICAL_NOTES"
fi

# Check form_soap for tobacco references  
echo "Checking SOAP notes..."
SOAP_NOTES=$(openemr_query "SELECT s.id, s.subjective, s.objective, s.assessment, s.plan FROM form_soap s JOIN forms f ON f.form_id = s.id AND f.formdir = 'soap' WHERE f.pid=$PATIENT_PID AND f.id > $LAST_FORM_ID" 2>/dev/null)
if [ -n "$SOAP_NOTES" ]; then
    echo "SOAP notes found: $SOAP_NOTES"
fi

# Check form_vitals for any new entries (often includes clinical notes)
echo "Checking vitals forms..."
VITALS=$(openemr_query "SELECT v.id, v.note FROM form_vitals v JOIN forms f ON f.form_id = v.id AND f.formdir = 'vitals' WHERE f.pid=$PATIENT_PID AND f.id > $LAST_FORM_ID" 2>/dev/null)
if [ -n "$VITALS" ]; then
    echo "Vitals found: $VITALS"
fi

# Check form_misc_billing_options and other misc forms
echo "Checking misc forms..."
MISC_FORMS=$(openemr_query "SELECT f.id, f.form_name, f.formdir FROM forms f WHERE f.pid=$PATIENT_PID AND f.id > $LAST_FORM_ID" 2>/dev/null)
echo "All new forms: $MISC_FORMS"

# Search across multiple tables for tobacco-related keywords
echo ""
echo "=== Searching for tobacco-related keywords ==="

# Search in encounter reason
REASON_SEARCH=$(openemr_query "SELECT id, reason FROM form_encounter WHERE pid=$PATIENT_PID AND (LOWER(reason) LIKE '%tobacco%' OR LOWER(reason) LIKE '%smoking%' OR LOWER(reason) LIKE '%cessation%' OR LOWER(reason) LIKE '%counseling%' OR LOWER(reason) LIKE '%nicotine%') ORDER BY id DESC LIMIT 3" 2>/dev/null)
if [ -n "$REASON_SEARCH" ]; then
    TOBACCO_FOUND="true"
    TOBACCO_CONTENT="$TOBACCO_CONTENT encounter_reason:$REASON_SEARCH"
    echo "Found in encounter reason: $REASON_SEARCH"
fi

# Search in clinical notes
CN_SEARCH=$(openemr_query "SELECT cn.id, SUBSTRING(cn.description, 1, 200) FROM form_clinical_notes cn JOIN forms f ON f.form_id = cn.id WHERE f.pid=$PATIENT_PID AND (LOWER(cn.description) LIKE '%tobacco%' OR LOWER(cn.description) LIKE '%smoking%' OR LOWER(cn.description) LIKE '%cessation%' OR LOWER(cn.description) LIKE '%counseling%' OR LOWER(cn.description) LIKE '%nicotine%' OR LOWER(cn.description) LIKE '%quit%') ORDER BY cn.id DESC LIMIT 3" 2>/dev/null)
if [ -n "$CN_SEARCH" ]; then
    TOBACCO_FOUND="true"
    TOBACCO_CONTENT="$TOBACCO_CONTENT clinical_notes:$CN_SEARCH"
    echo "Found in clinical notes: $CN_SEARCH"
fi

# Search in SOAP notes
SOAP_SEARCH=$(openemr_query "SELECT s.id, SUBSTRING(CONCAT(s.subjective, ' ', s.assessment, ' ', s.plan), 1, 300) FROM form_soap s JOIN forms f ON f.form_id = s.id WHERE f.pid=$PATIENT_PID AND (LOWER(CONCAT(s.subjective, s.objective, s.assessment, s.plan)) LIKE '%tobacco%' OR LOWER(CONCAT(s.subjective, s.objective, s.assessment, s.plan)) LIKE '%smoking%' OR LOWER(CONCAT(s.subjective, s.objective, s.assessment, s.plan)) LIKE '%cessation%' OR LOWER(CONCAT(s.subjective, s.objective, s.assessment, s.plan)) LIKE '%counseling%') ORDER BY s.id DESC LIMIT 3" 2>/dev/null)
if [ -n "$SOAP_SEARCH" ]; then
    TOBACCO_FOUND="true"
    TOBACCO_CONTENT="$TOBACCO_CONTENT soap:$SOAP_SEARCH"
    echo "Found in SOAP: $SOAP_SEARCH"
fi

# Check for time documentation (e.g., "10 minutes", "10 min")
TIME_FOUND="false"
TIME_SEARCH=$(openemr_query "SELECT cn.id FROM form_clinical_notes cn JOIN forms f ON f.form_id = cn.id WHERE f.pid=$PATIENT_PID AND (cn.description LIKE '%10 min%' OR cn.description LIKE '%10min%' OR cn.description LIKE '%minutes%') ORDER BY cn.id DESC LIMIT 1" 2>/dev/null)
if [ -n "$TIME_SEARCH" ]; then
    TIME_FOUND="true"
    echo "Time documentation found"
fi

# Check for follow-up plan (e.g., "follow-up", "follow up", "callback", "2 week")
FOLLOWUP_FOUND="false"
FOLLOWUP_SEARCH=$(openemr_query "SELECT cn.id FROM form_clinical_notes cn JOIN forms f ON f.form_id = cn.id WHERE f.pid=$PATIENT_PID AND (LOWER(cn.description) LIKE '%follow%up%' OR LOWER(cn.description) LIKE '%follow-up%' OR LOWER(cn.description) LIKE '%callback%' OR LOWER(cn.description) LIKE '%2 week%' OR LOWER(cn.description) LIKE '%patch%' OR LOWER(cn.description) LIKE '%prescription%') ORDER BY cn.id DESC LIMIT 1" 2>/dev/null)
if [ -n "$FOLLOWUP_SEARCH" ]; then
    FOLLOWUP_FOUND="true"
    echo "Follow-up plan found"
fi

# Also check SOAP plan field for follow-up
if [ "$FOLLOWUP_FOUND" = "false" ]; then
    SOAP_FOLLOWUP=$(openemr_query "SELECT s.id FROM form_soap s JOIN forms f ON f.form_id = s.id WHERE f.pid=$PATIENT_PID AND (LOWER(s.plan) LIKE '%follow%' OR LOWER(s.plan) LIKE '%callback%' OR LOWER(s.plan) LIKE '%patch%' OR LOWER(s.plan) LIKE '%week%') ORDER BY s.id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$SOAP_FOLLOWUP" ]; then
        FOLLOWUP_FOUND="true"
        echo "Follow-up plan found in SOAP"
    fi
fi

# Get full content of newest clinical note for detailed analysis
NEWEST_NOTE_CONTENT=""
NEWEST_NOTE=$(openemr_query "SELECT cn.description FROM form_clinical_notes cn JOIN forms f ON f.form_id = cn.id WHERE f.pid=$PATIENT_PID AND f.id > $LAST_FORM_ID ORDER BY cn.id DESC LIMIT 1" 2>/dev/null)
if [ -n "$NEWEST_NOTE" ]; then
    NEWEST_NOTE_CONTENT="$NEWEST_NOTE"
fi

# Escape special characters for JSON
ENCOUNTER_REASON_ESC=$(echo "$ENCOUNTER_REASON" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)
TOBACCO_CONTENT_ESC=$(echo "$TOBACCO_CONTENT" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 1000)
NEWEST_NOTE_ESC=$(echo "$NEWEST_NOTE_CONTENT" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 2000)

# Create result JSON
TEMP_JSON=$(mktemp /tmp/tobacco_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_date": "$TASK_DATE",
    "initial_encounter_count": ${INITIAL_ENCOUNTER_COUNT:-0},
    "current_encounter_count": ${CURRENT_ENCOUNTER_COUNT:-0},
    "initial_forms_count": ${INITIAL_FORMS_COUNT:-0},
    "current_forms_count": ${CURRENT_FORMS_COUNT:-0},
    "encounter_found": $ENCOUNTER_FOUND,
    "encounter": {
        "id": "$ENCOUNTER_ID",
        "date": "$ENCOUNTER_DATE",
        "reason": "$ENCOUNTER_REASON_ESC",
        "encounter_num": "$ENCOUNTER_NUM"
    },
    "tobacco_reference_found": $TOBACCO_FOUND,
    "tobacco_content": "$TOBACCO_CONTENT_ESC",
    "newest_note_content": "$NEWEST_NOTE_ESC",
    "time_documented": $TIME_FOUND,
    "followup_documented": $FOLLOWUP_FOUND,
    "new_forms_count": $((CURRENT_FORMS_COUNT - INITIAL_FORMS_COUNT)),
    "new_encounters_count": $((CURRENT_ENCOUNTER_COUNT - INITIAL_ENCOUNTER_COUNT)),
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final location
rm -f /tmp/tobacco_counseling_result.json 2>/dev/null || sudo rm -f /tmp/tobacco_counseling_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/tobacco_counseling_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/tobacco_counseling_result.json
chmod 666 /tmp/tobacco_counseling_result.json 2>/dev/null || sudo chmod 666 /tmp/tobacco_counseling_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/tobacco_counseling_result.json"
cat /tmp/tobacco_counseling_result.json

echo ""
echo "=== Export Complete ==="
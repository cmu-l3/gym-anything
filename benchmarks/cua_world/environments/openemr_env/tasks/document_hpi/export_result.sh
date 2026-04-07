#!/bin/bash
# Export script for Document HPI Task

echo "=== Exporting Document HPI Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot first
sleep 1
take_screenshot /tmp/task_final_state.png
echo "Final screenshot saved"

# Target patient
PATIENT_PID=3

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial counts
INITIAL_FORM_COUNT=$(cat /tmp/initial_form_count.txt 2>/dev/null || echo "0")
INITIAL_ENCOUNTER_COUNT=$(cat /tmp/initial_encounter_count.txt 2>/dev/null || echo "0")
INITIAL_SOAP_COUNT=$(cat /tmp/initial_soap_count.txt 2>/dev/null || echo "0")
INITIAL_CLINICAL_COUNT=$(cat /tmp/initial_clinical_count.txt 2>/dev/null || echo "0")

# Get current counts
CURRENT_FORM_COUNT=$(openemr_query "SELECT COUNT(*) FROM forms WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_ENCOUNTER_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_SOAP_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_soap WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_CLINICAL_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_clinical_notes WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo "Form counts: initial=$INITIAL_FORM_COUNT, current=$CURRENT_FORM_COUNT"
echo "Encounter counts: initial=$INITIAL_ENCOUNTER_COUNT, current=$CURRENT_ENCOUNTER_COUNT"
echo "SOAP counts: initial=$INITIAL_SOAP_COUNT, current=$CURRENT_SOAP_COUNT"
echo "Clinical note counts: initial=$INITIAL_CLINICAL_COUNT, current=$CURRENT_CLINICAL_COUNT"

# Check if new forms/documentation were added
NEW_FORMS_ADDED="false"
if [ "$CURRENT_FORM_COUNT" -gt "$INITIAL_FORM_COUNT" ]; then
    NEW_FORMS_ADDED="true"
fi

NEW_ENCOUNTER_ADDED="false"
if [ "$CURRENT_ENCOUNTER_COUNT" -gt "$INITIAL_ENCOUNTER_COUNT" ]; then
    NEW_ENCOUNTER_ADDED="true"
fi

# Query for the most recent SOAP note content (common HPI location)
echo ""
echo "=== Querying for HPI documentation ==="

SOAP_CONTENT=""
if [ "$CURRENT_SOAP_COUNT" -gt "0" ]; then
    SOAP_CONTENT=$(openemr_query "SELECT subjective, objective, assessment, plan FROM form_soap WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
    echo "Most recent SOAP note content:"
    echo "$SOAP_CONTENT"
fi

# Query for clinical notes
CLINICAL_NOTE_CONTENT=""
if [ "$CURRENT_CLINICAL_COUNT" -gt "0" ]; then
    CLINICAL_NOTE_CONTENT=$(openemr_query "SELECT description, clinical_notes_type FROM form_clinical_notes WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
    echo "Most recent clinical note content:"
    echo "$CLINICAL_NOTE_CONTENT"
fi

# Query encounter reason field (sometimes HPI is stored here)
ENCOUNTER_REASON=""
if [ "$CURRENT_ENCOUNTER_COUNT" -gt "0" ]; then
    ENCOUNTER_REASON=$(openemr_query "SELECT reason FROM form_encounter WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
    echo "Most recent encounter reason:"
    echo "$ENCOUNTER_REASON"
fi

# Query for any form with text content for this patient
echo ""
echo "=== Checking all recent forms ==="
ALL_RECENT_FORMS=$(openemr_query "SELECT f.id, f.form_name, f.formdir, f.encounter FROM forms f WHERE f.pid=$PATIENT_PID ORDER BY f.id DESC LIMIT 10" 2>/dev/null)
echo "Recent forms:"
echo "$ALL_RECENT_FORMS"

# Check form_vitals for any notes (some HPI might be documented there)
VITALS_NOTES=""
VITALS_NOTES=$(openemr_query "SELECT note FROM form_vitals WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")

# Combine all text content for HPI element analysis
ALL_DOCUMENTATION="$SOAP_CONTENT $CLINICAL_NOTE_CONTENT $ENCOUNTER_REASON $VITALS_NOTES"

# Analyze HPI elements present
echo ""
echo "=== Analyzing HPI elements ==="

# Check for each HPI element (case-insensitive)
DOC_LOWER=$(echo "$ALL_DOCUMENTATION" | tr '[:upper:]' '[:lower:]')

HAS_LOCATION="false"
if echo "$DOC_LOWER" | grep -qE "(back|lumbar|lower)"; then
    HAS_LOCATION="true"
    echo "Found LOCATION element"
fi

HAS_QUALITY="false"
if echo "$DOC_LOWER" | grep -qE "(dull|aching|sharp|twinge)"; then
    HAS_QUALITY="true"
    echo "Found QUALITY element"
fi

HAS_SEVERITY="false"
if echo "$DOC_LOWER" | grep -qE "(6/10|6 out of|six out|moderate)"; then
    HAS_SEVERITY="true"
    echo "Found SEVERITY element"
fi

HAS_DURATION="false"
if echo "$DOC_LOWER" | grep -qE "(5 day|five day|days ago)"; then
    HAS_DURATION="true"
    echo "Found DURATION element"
fi

HAS_TIMING="false"
if echo "$DOC_LOWER" | grep -qE "(morning|sitting|prolonged)"; then
    HAS_TIMING="true"
    echo "Found TIMING element"
fi

HAS_CONTEXT="false"
if echo "$DOC_LOWER" | grep -qE "(lifting|boxes|moving|furniture)"; then
    HAS_CONTEXT="true"
    echo "Found CONTEXT element"
fi

HAS_MODIFYING="false"
if echo "$DOC_LOWER" | grep -qE "(bending|rest|ibuprofen|worse|better|relief)"; then
    HAS_MODIFYING="true"
    echo "Found MODIFYING FACTORS element"
fi

HAS_ASSOCIATED="false"
if echo "$DOC_LOWER" | grep -qE "(denies|no numbness|no tingling|negative|no radiation|no weakness|no leg)"; then
    HAS_ASSOCIATED="true"
    echo "Found ASSOCIATED SIGNS/SYMPTOMS element"
fi

# Count total elements found
ELEMENTS_COUNT=0
[ "$HAS_LOCATION" = "true" ] && ELEMENTS_COUNT=$((ELEMENTS_COUNT + 1))
[ "$HAS_QUALITY" = "true" ] && ELEMENTS_COUNT=$((ELEMENTS_COUNT + 1))
[ "$HAS_SEVERITY" = "true" ] && ELEMENTS_COUNT=$((ELEMENTS_COUNT + 1))
[ "$HAS_DURATION" = "true" ] && ELEMENTS_COUNT=$((ELEMENTS_COUNT + 1))
[ "$HAS_TIMING" = "true" ] && ELEMENTS_COUNT=$((ELEMENTS_COUNT + 1))
[ "$HAS_CONTEXT" = "true" ] && ELEMENTS_COUNT=$((ELEMENTS_COUNT + 1))
[ "$HAS_MODIFYING" = "true" ] && ELEMENTS_COUNT=$((ELEMENTS_COUNT + 1))
[ "$HAS_ASSOCIATED" = "true" ] && ELEMENTS_COUNT=$((ELEMENTS_COUNT + 1))

echo ""
echo "Total HPI elements found: $ELEMENTS_COUNT / 8"

# Escape special characters for JSON
SOAP_ESCAPED=$(echo "$SOAP_CONTENT" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)
CLINICAL_ESCAPED=$(echo "$CLINICAL_NOTE_CONTENT" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)
ENCOUNTER_ESCAPED=$(echo "$ENCOUNTER_REASON" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)
ALL_DOC_ESCAPED=$(echo "$ALL_DOCUMENTATION" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 1000)

# Create result JSON
TEMP_JSON=$(mktemp /tmp/hpi_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "counts": {
        "initial_forms": $INITIAL_FORM_COUNT,
        "current_forms": $CURRENT_FORM_COUNT,
        "initial_encounters": $INITIAL_ENCOUNTER_COUNT,
        "current_encounters": $CURRENT_ENCOUNTER_COUNT,
        "initial_soap": $INITIAL_SOAP_COUNT,
        "current_soap": $CURRENT_SOAP_COUNT,
        "initial_clinical": $INITIAL_CLINICAL_COUNT,
        "current_clinical": $CURRENT_CLINICAL_COUNT
    },
    "new_documentation_added": $NEW_FORMS_ADDED,
    "new_encounter_added": $NEW_ENCOUNTER_ADDED,
    "hpi_elements": {
        "location": $HAS_LOCATION,
        "quality": $HAS_QUALITY,
        "severity": $HAS_SEVERITY,
        "duration": $HAS_DURATION,
        "timing": $HAS_TIMING,
        "context": $HAS_CONTEXT,
        "modifying": $HAS_MODIFYING,
        "associated": $HAS_ASSOCIATED,
        "total_count": $ELEMENTS_COUNT
    },
    "documentation_content": {
        "soap_note": "$SOAP_ESCAPED",
        "clinical_note": "$CLINICAL_ESCAPED",
        "encounter_reason": "$ENCOUNTER_ESCAPED",
        "all_text": "$ALL_DOC_ESCAPED"
    },
    "screenshot_exists": $([ -f "/tmp/task_final_state.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result JSON
rm -f /tmp/document_hpi_result.json 2>/dev/null || sudo rm -f /tmp/document_hpi_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/document_hpi_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/document_hpi_result.json
chmod 666 /tmp/document_hpi_result.json 2>/dev/null || sudo chmod 666 /tmp/document_hpi_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/document_hpi_result.json"
cat /tmp/document_hpi_result.json
echo ""
echo "=== Export Complete ==="
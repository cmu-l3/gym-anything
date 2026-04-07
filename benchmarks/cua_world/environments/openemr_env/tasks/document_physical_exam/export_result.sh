#!/bin/bash
# Export script for Document Physical Exam task

echo "=== Exporting Document Physical Exam Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Get task parameters
PATIENT_PID=3
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
ENCOUNTER_ID=$(cat /tmp/target_encounter_id.txt 2>/dev/null || echo "0")
INITIAL_FORMS=$(cat /tmp/initial_form_count.txt 2>/dev/null || echo "0")
INITIAL_SOAP=$(cat /tmp/initial_soap_count.txt 2>/dev/null || echo "0")

echo "Task parameters:"
echo "  Patient PID: $PATIENT_PID"
echo "  Encounter ID: $ENCOUNTER_ID"
echo "  Task start: $TASK_START"
echo "  Task end: $TASK_END"

# Get current form counts
CURRENT_FORMS=$(openemr_query "SELECT COUNT(*) FROM forms WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_SOAP=$(openemr_query "SELECT COUNT(*) FROM form_soap WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo "Form counts: initial=$INITIAL_FORMS, current=$CURRENT_FORMS"
echo "SOAP counts: initial=$INITIAL_SOAP, current=$CURRENT_SOAP"

# Query for recent forms for this patient
echo ""
echo "=== Recent forms for patient ==="
RECENT_FORMS=$(openemr_query "SELECT id, date, encounter, form_name, formdir FROM forms WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 10" 2>/dev/null)
echo "$RECENT_FORMS"

# Check for SOAP notes (most common form for physical exam)
echo ""
echo "=== Checking SOAP notes ==="
SOAP_DATA=$(openemr_query "SELECT id, pid, date, subjective, objective, assessment, plan FROM form_soap WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 3" 2>/dev/null)
echo "SOAP data found: $(echo "$SOAP_DATA" | wc -l) records"

# Get the most recent SOAP note content
LATEST_SOAP=""
SOAP_ID=""
SOAP_OBJECTIVE=""
if [ -n "$SOAP_DATA" ]; then
    SOAP_ID=$(echo "$SOAP_DATA" | head -1 | cut -f1)
    SOAP_OBJECTIVE=$(openemr_query "SELECT objective FROM form_soap WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
    echo "Latest SOAP ID: $SOAP_ID"
    echo "Objective content length: $(echo -n "$SOAP_OBJECTIVE" | wc -c) chars"
fi

# Check for clinical notes
echo ""
echo "=== Checking clinical notes ==="
CLINICAL_NOTES=$(openemr_query "SELECT id, pid, date, description FROM form_clinical_notes WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 3" 2>/dev/null)
echo "Clinical notes found: $(echo "$CLINICAL_NOTES" | wc -l) records"

# Get latest clinical note content
LATEST_CLINICAL_NOTE=""
CLINICAL_NOTE_ID=""
if [ -n "$CLINICAL_NOTES" ]; then
    CLINICAL_NOTE_ID=$(echo "$CLINICAL_NOTES" | head -1 | cut -f1)
    LATEST_CLINICAL_NOTE=$(openemr_query "SELECT description FROM form_clinical_notes WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
    echo "Latest clinical note ID: $CLINICAL_NOTE_ID"
fi

# Check for vitals (sometimes physical exam is entered here)
echo ""
echo "=== Checking vitals ==="
VITALS_DATA=$(openemr_query "SELECT id, pid, date, note FROM form_vitals WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 3" 2>/dev/null)
echo "Vitals records found: $(echo "$VITALS_DATA" | wc -l) records"

# Combine all possible physical exam content for analysis
ALL_CONTENT=""

if [ -n "$SOAP_OBJECTIVE" ]; then
    ALL_CONTENT="$ALL_CONTENT SOAP_OBJECTIVE: $SOAP_OBJECTIVE"
fi

if [ -n "$LATEST_CLINICAL_NOTE" ]; then
    ALL_CONTENT="$ALL_CONTENT CLINICAL_NOTE: $LATEST_CLINICAL_NOTE"
fi

# Check for specific clinical terms indicating physical exam was documented
CONTENT_LOWER=$(echo "$ALL_CONTENT" | tr '[:upper:]' '[:lower:]')

# Check for required body systems
HAS_GENERAL="false"
HAS_HEENT="false"
HAS_NECK="false"
HAS_CARDIOVASCULAR="false"
HAS_RESPIRATORY="false"
HAS_ABDOMEN="false"

if echo "$CONTENT_LOWER" | grep -qE "(general|alert|oriented|no acute distress|appearance)"; then
    HAS_GENERAL="true"
    echo "Found: General examination"
fi

if echo "$CONTENT_LOWER" | grep -qE "(heent|head|eyes|ears|nose|throat|perrla|normocephalic|tms|oropharynx)"; then
    HAS_HEENT="true"
    echo "Found: HEENT examination"
fi

if echo "$CONTENT_LOWER" | grep -qE "(neck|supple|lymphadenopathy|thyromegaly|jvd|jugular)"; then
    HAS_NECK="true"
    echo "Found: Neck examination"
fi

if echo "$CONTENT_LOWER" | grep -qE "(cardiovascular|heart|cardiac|rhythm|murmur|s1|s2|pulse|rrr|regular rate)"; then
    HAS_CARDIOVASCULAR="true"
    echo "Found: Cardiovascular examination"
fi

if echo "$CONTENT_LOWER" | grep -qE "(respiratory|lung|breath sounds|auscultation|wheeze|rhonchi|rales|chest)"; then
    HAS_RESPIRATORY="true"
    echo "Found: Respiratory examination"
fi

if echo "$CONTENT_LOWER" | grep -qE "(abdomen|abdominal|bowel sounds|tender|distended|hepatosplenomegaly|soft)"; then
    HAS_ABDOMEN="true"
    echo "Found: Abdominal examination"
fi

# Count systems documented
SYSTEMS_DOCUMENTED=0
[ "$HAS_GENERAL" = "true" ] && SYSTEMS_DOCUMENTED=$((SYSTEMS_DOCUMENTED + 1))
[ "$HAS_HEENT" = "true" ] && SYSTEMS_DOCUMENTED=$((SYSTEMS_DOCUMENTED + 1))
[ "$HAS_NECK" = "true" ] && SYSTEMS_DOCUMENTED=$((SYSTEMS_DOCUMENTED + 1))
[ "$HAS_CARDIOVASCULAR" = "true" ] && SYSTEMS_DOCUMENTED=$((SYSTEMS_DOCUMENTED + 1))
[ "$HAS_RESPIRATORY" = "true" ] && SYSTEMS_DOCUMENTED=$((SYSTEMS_DOCUMENTED + 1))
[ "$HAS_ABDOMEN" = "true" ] && SYSTEMS_DOCUMENTED=$((SYSTEMS_DOCUMENTED + 1))

echo ""
echo "Body systems documented: $SYSTEMS_DOCUMENTED / 6"

# Determine if new form was created
NEW_FORM_CREATED="false"
if [ "$CURRENT_FORMS" -gt "$INITIAL_FORMS" ] || [ "$CURRENT_SOAP" -gt "$INITIAL_SOAP" ]; then
    NEW_FORM_CREATED="true"
fi

# Escape content for JSON
SOAP_OBJECTIVE_ESCAPED=$(echo "$SOAP_OBJECTIVE" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 2000)
CLINICAL_NOTE_ESCAPED=$(echo "$LATEST_CLINICAL_NOTE" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 2000)

# Create result JSON
TEMP_JSON=$(mktemp /tmp/physical_exam_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "encounter_id": $ENCOUNTER_ID,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_form_count": $INITIAL_FORMS,
    "current_form_count": $CURRENT_FORMS,
    "initial_soap_count": $INITIAL_SOAP,
    "current_soap_count": $CURRENT_SOAP,
    "new_form_created": $NEW_FORM_CREATED,
    "soap_note_id": "$SOAP_ID",
    "clinical_note_id": "$CLINICAL_NOTE_ID",
    "soap_objective_content": "$SOAP_OBJECTIVE_ESCAPED",
    "clinical_note_content": "$CLINICAL_NOTE_ESCAPED",
    "systems_documented": {
        "general": $HAS_GENERAL,
        "heent": $HAS_HEENT,
        "neck": $HAS_NECK,
        "cardiovascular": $HAS_CARDIOVASCULAR,
        "respiratory": $HAS_RESPIRATORY,
        "abdomen": $HAS_ABDOMEN,
        "total_count": $SYSTEMS_DOCUMENTED
    },
    "screenshot_path": "/tmp/task_final_state.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/physical_exam_result.json 2>/dev/null || sudo rm -f /tmp/physical_exam_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/physical_exam_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/physical_exam_result.json
chmod 666 /tmp/physical_exam_result.json 2>/dev/null || sudo chmod 666 /tmp/physical_exam_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/physical_exam_result.json"
cat /tmp/physical_exam_result.json

echo ""
echo "=== Export Complete ==="
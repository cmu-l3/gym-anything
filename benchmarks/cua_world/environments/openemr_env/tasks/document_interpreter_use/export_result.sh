#!/bin/bash
# Export script for Document Interpreter Use Task

echo "=== Exporting Document Interpreter Use Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Configuration
PATIENT_PID=5
PATIENT_FNAME="Maria"
PATIENT_LNAME="Santos"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png

# Get task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
ENCOUNTER_ID=$(cat /tmp/task_encounter_id.txt 2>/dev/null || echo "0")

# Get initial counts
INITIAL_NOTES_COUNT=$(cat /tmp/initial_notes_count.txt 2>/dev/null || echo "0")
INITIAL_FORMS_COUNT=$(cat /tmp/initial_forms_count.txt 2>/dev/null || echo "0")

# Get current counts
CURRENT_NOTES_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_clinical_notes WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_FORMS_COUNT=$(openemr_query "SELECT COUNT(*) FROM forms WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo "Notes count: initial=$INITIAL_NOTES_COUNT, current=$CURRENT_NOTES_COUNT"
echo "Forms count: initial=$INITIAL_FORMS_COUNT, current=$CURRENT_FORMS_COUNT"

# Search for interpreter documentation in clinical notes
echo ""
echo "=== Searching for interpreter documentation ==="

# Query clinical notes for interpreter-related content
INTERPRETER_NOTES=$(openemr_query "
SELECT id, pid, encounter, clinical_notes_type, description, date 
FROM form_clinical_notes 
WHERE pid=$PATIENT_PID 
AND (
    LOWER(description) LIKE '%interpreter%' 
    OR LOWER(description) LIKE '%spanish%'
    OR LOWER(description) LIKE '%cyracom%'
    OR LOWER(description) LIKE '%language%'
)
ORDER BY id DESC 
LIMIT 5
" 2>/dev/null)

echo "Interpreter-related clinical notes found:"
echo "$INTERPRETER_NOTES"

# Also check form_misc_billing_options or other encounter forms
BILLING_NOTES=$(openemr_query "
SELECT id, pid, encounter 
FROM form_misc_billing_options 
WHERE pid=$PATIENT_PID 
ORDER BY id DESC 
LIMIT 3
" 2>/dev/null)

# Check encounter notes/comments
ENCOUNTER_NOTES=$(openemr_query "
SELECT id, date, reason, pc_catid 
FROM form_encounter 
WHERE pid=$PATIENT_PID 
AND date >= DATE_SUB(CURDATE(), INTERVAL 1 DAY)
ORDER BY id DESC 
LIMIT 3
" 2>/dev/null)
echo "Recent encounters:"
echo "$ENCOUNTER_NOTES"

# Search for any form containing interpreter keywords across multiple tables
# Check forms table for any new forms
NEW_FORMS=$(openemr_query "
SELECT f.id, f.form_name, f.formdir, f.encounter
FROM forms f
WHERE f.pid=$PATIENT_PID
ORDER BY f.id DESC
LIMIT 10
" 2>/dev/null)
echo "Recent forms:"
echo "$NEW_FORMS"

# Parse interpreter documentation for verification
INTERPRETER_DOC_FOUND="false"
LANGUAGE_FOUND="false"
TYPE_FOUND="false"
PROVIDER_FOUND="false"
DURATION_FOUND="false"
NOTE_CONTENT=""

# Get the most recent clinical note for this patient
LATEST_NOTE=$(openemr_query "
SELECT id, description, date 
FROM form_clinical_notes 
WHERE pid=$PATIENT_PID 
ORDER BY id DESC 
LIMIT 1
" 2>/dev/null)

if [ -n "$LATEST_NOTE" ]; then
    NOTE_ID=$(echo "$LATEST_NOTE" | cut -f1)
    NOTE_CONTENT=$(echo "$LATEST_NOTE" | cut -f2)
    NOTE_DATE=$(echo "$LATEST_NOTE" | cut -f3)
    
    echo ""
    echo "Latest clinical note (ID: $NOTE_ID):"
    echo "$NOTE_CONTENT"
    
    # Check for interpreter documentation
    NOTE_LOWER=$(echo "$NOTE_CONTENT" | tr '[:upper:]' '[:lower:]')
    
    if echo "$NOTE_LOWER" | grep -qi "interpreter"; then
        INTERPRETER_DOC_FOUND="true"
    fi
    
    if echo "$NOTE_LOWER" | grep -qi "spanish"; then
        LANGUAGE_FOUND="true"
    fi
    
    if echo "$NOTE_LOWER" | grep -qiE "telephone|phone|telephonic"; then
        TYPE_FOUND="true"
    fi
    
    if echo "$NOTE_LOWER" | grep -qi "cyracom"; then
        PROVIDER_FOUND="true"
    fi
    
    if echo "$NOTE_LOWER" | grep -qiE "25|twenty.?five|minutes|duration"; then
        DURATION_FOUND="true"
    fi
fi

# Also check pnotes (patient notes) table
PATIENT_NOTES=$(openemr_query "
SELECT id, body, date
FROM pnotes
WHERE pid=$PATIENT_PID
AND (LOWER(body) LIKE '%interpreter%' OR LOWER(body) LIKE '%spanish%')
ORDER BY id DESC
LIMIT 3
" 2>/dev/null)

if [ -n "$PATIENT_NOTES" ] && [ "$INTERPRETER_DOC_FOUND" = "false" ]; then
    echo ""
    echo "Found patient notes with interpreter keywords:"
    echo "$PATIENT_NOTES"
    INTERPRETER_DOC_FOUND="true"
    
    PNOTE_CONTENT=$(echo "$PATIENT_NOTES" | head -1 | cut -f2)
    PNOTE_LOWER=$(echo "$PNOTE_CONTENT" | tr '[:upper:]' '[:lower:]')
    
    if echo "$PNOTE_LOWER" | grep -qi "spanish"; then
        LANGUAGE_FOUND="true"
    fi
    
    if echo "$PNOTE_LOWER" | grep -qiE "telephone|phone"; then
        TYPE_FOUND="true"
    fi
    
    if echo "$PNOTE_LOWER" | grep -qi "cyracom"; then
        PROVIDER_FOUND="true"
    fi
    
    if echo "$PNOTE_LOWER" | grep -qiE "25|minutes|duration"; then
        DURATION_FOUND="true"
    fi
    
    NOTE_CONTENT="$PNOTE_CONTENT"
fi

# Check transactions table (sometimes used for encounter documentation)
TRANSACTIONS=$(openemr_query "
SELECT id, body, date
FROM transactions
WHERE pid=$PATIENT_PID
ORDER BY id DESC
LIMIT 3
" 2>/dev/null)

# Escape special characters for JSON
NOTE_CONTENT_ESCAPED=$(echo "$NOTE_CONTENT" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g' | tr '\n' ' ' | head -c 500)

# Check if new documentation was added (comparing counts)
NEW_NOTES_ADDED="false"
if [ "$CURRENT_NOTES_COUNT" -gt "$INITIAL_NOTES_COUNT" ]; then
    NEW_NOTES_ADDED="true"
fi

NEW_FORMS_ADDED="false"
if [ "$CURRENT_FORMS_COUNT" -gt "$INITIAL_FORMS_COUNT" ]; then
    NEW_FORMS_ADDED="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/interpreter_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "patient_pid": $PATIENT_PID,
    "patient_fname": "$PATIENT_FNAME",
    "patient_lname": "$PATIENT_LNAME",
    "encounter_id": "$ENCOUNTER_ID",
    "initial_notes_count": $INITIAL_NOTES_COUNT,
    "current_notes_count": $CURRENT_NOTES_COUNT,
    "initial_forms_count": $INITIAL_FORMS_COUNT,
    "current_forms_count": $CURRENT_FORMS_COUNT,
    "new_notes_added": $NEW_NOTES_ADDED,
    "new_forms_added": $NEW_FORMS_ADDED,
    "documentation_checks": {
        "interpreter_doc_found": $INTERPRETER_DOC_FOUND,
        "language_documented": $LANGUAGE_FOUND,
        "interpreter_type_documented": $TYPE_FOUND,
        "provider_documented": $PROVIDER_FOUND,
        "duration_documented": $DURATION_FOUND
    },
    "note_content_sample": "$NOTE_CONTENT_ESCAPED",
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/interpreter_use_result.json 2>/dev/null || sudo rm -f /tmp/interpreter_use_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/interpreter_use_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/interpreter_use_result.json
chmod 666 /tmp/interpreter_use_result.json 2>/dev/null || sudo chmod 666 /tmp/interpreter_use_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/interpreter_use_result.json"
cat /tmp/interpreter_use_result.json
echo ""
echo "=== Export Complete ==="
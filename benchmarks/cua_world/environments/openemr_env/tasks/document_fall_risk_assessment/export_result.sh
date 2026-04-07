#!/bin/bash
# Export script for Fall Risk Assessment Task

echo "=== Exporting Fall Risk Assessment Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true
echo "Final screenshot saved to /tmp/task_final_state.png"

# Target patient
PATIENT_PID=4

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial counts
INITIAL_FORMS=$(cat /tmp/initial_form_count.txt 2>/dev/null || echo "0")
INITIAL_NOTES=$(cat /tmp/initial_note_count.txt 2>/dev/null || echo "0")
INITIAL_ENCOUNTERS=$(cat /tmp/initial_encounter_count.txt 2>/dev/null || echo "0")
INITIAL_MAX_FORM_ID=$(cat /tmp/initial_max_form_id.txt 2>/dev/null || echo "0")
INITIAL_MAX_NOTE_ID=$(cat /tmp/initial_max_note_id.txt 2>/dev/null || echo "0")

# Get current counts
CURRENT_FORMS=$(openemr_query "SELECT COUNT(*) FROM forms WHERE pid=$PATIENT_PID AND deleted=0" 2>/dev/null || echo "0")
CURRENT_NOTES=$(openemr_query "SELECT COUNT(*) FROM pnotes WHERE pid=$PATIENT_PID AND deleted=0" 2>/dev/null || echo "0")
CURRENT_ENCOUNTERS=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo "Form count: initial=$INITIAL_FORMS, current=$CURRENT_FORMS"
echo "Note count: initial=$INITIAL_NOTES, current=$CURRENT_NOTES"
echo "Encounter count: initial=$INITIAL_ENCOUNTERS, current=$CURRENT_ENCOUNTERS"

# Calculate new entries
NEW_FORMS=$((CURRENT_FORMS - INITIAL_FORMS))
NEW_NOTES=$((CURRENT_NOTES - INITIAL_NOTES))
NEW_ENCOUNTERS=$((CURRENT_ENCOUNTERS - INITIAL_ENCOUNTERS))

echo "New forms: $NEW_FORMS, New notes: $NEW_NOTES, New encounters: $NEW_ENCOUNTERS"

# Query for note content from pnotes table
echo ""
echo "=== Querying patient notes ==="
NOTES_CONTENT=$(openemr_query "SELECT id, date, body FROM pnotes WHERE pid=$PATIENT_PID AND deleted=0 ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "Recent notes:"
echo "$NOTES_CONTENT"

# Query for new notes specifically (id > initial max)
echo ""
echo "=== Querying NEW notes (created during task) ==="
NEW_NOTES_CONTENT=$(openemr_query "SELECT id, date, body FROM pnotes WHERE pid=$PATIENT_PID AND deleted=0 AND id > $INITIAL_MAX_NOTE_ID ORDER BY id DESC" 2>/dev/null)
echo "New notes content:"
echo "$NEW_NOTES_CONTENT"

# Query for encounter reasons
echo ""
echo "=== Querying encounters ==="
ENCOUNTER_REASONS=$(openemr_query "SELECT id, date, reason FROM form_encounter WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "Recent encounters:"
echo "$ENCOUNTER_REASONS"

# Query forms table for any clinical forms
echo ""
echo "=== Querying forms ==="
FORMS_DATA=$(openemr_query "SELECT id, date, form_name, formdir FROM forms WHERE pid=$PATIENT_PID AND deleted=0 ORDER BY id DESC LIMIT 10" 2>/dev/null)
echo "Recent forms:"
echo "$FORMS_DATA"

# Check for fall-related keywords in all text content
FALL_CONTENT_FOUND="false"
KEYWORDS_FOUND=""
SCORE_FOUND="false"
INTERVENTION_FOUND="false"

# Combine all text content for keyword search
ALL_TEXT=$(echo "$NOTES_CONTENT $NEW_NOTES_CONTENT $ENCOUNTER_REASONS" | tr '[:upper:]' '[:lower:]')

# Check for fall-related keywords
for keyword in "fall" "risk" "morse" "gait" "ambulatory" "walker" "impaired" "precaution" "assessment"; do
    if echo "$ALL_TEXT" | grep -q "$keyword"; then
        FALL_CONTENT_FOUND="true"
        KEYWORDS_FOUND="$KEYWORDS_FOUND $keyword"
    fi
done

# Check for score
if echo "$ALL_TEXT" | grep -qE "(90|high.?risk|high risk)"; then
    SCORE_FOUND="true"
fi

# Check for intervention
for keyword in "precaution" "intervention" "education" "protocol" "prevention"; do
    if echo "$ALL_TEXT" | grep -q "$keyword"; then
        INTERVENTION_FOUND="true"
        break
    fi
done

echo ""
echo "=== Content Analysis ==="
echo "Fall content found: $FALL_CONTENT_FOUND"
echo "Keywords found: $KEYWORDS_FOUND"
echo "Score (90/high risk) found: $SCORE_FOUND"
echo "Intervention found: $INTERVENTION_FOUND"

# Extract the actual note body for the newest note if it exists
NEWEST_NOTE_BODY=""
if [ -n "$NEW_NOTES_CONTENT" ]; then
    # Get just the body (third field) from the newest note
    NEWEST_NOTE_BODY=$(echo "$NEW_NOTES_CONTENT" | head -1 | cut -f3-)
fi

# Escape special characters for JSON
NEWEST_NOTE_BODY_ESCAPED=$(echo "$NEWEST_NOTE_BODY" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 2000)
KEYWORDS_FOUND_ESCAPED=$(echo "$KEYWORDS_FOUND" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/fall_risk_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_counts": {
        "forms": ${INITIAL_FORMS:-0},
        "notes": ${INITIAL_NOTES:-0},
        "encounters": ${INITIAL_ENCOUNTERS:-0},
        "max_form_id": ${INITIAL_MAX_FORM_ID:-0},
        "max_note_id": ${INITIAL_MAX_NOTE_ID:-0}
    },
    "current_counts": {
        "forms": ${CURRENT_FORMS:-0},
        "notes": ${CURRENT_NOTES:-0},
        "encounters": ${CURRENT_ENCOUNTERS:-0}
    },
    "new_entries": {
        "forms": ${NEW_FORMS:-0},
        "notes": ${NEW_NOTES:-0},
        "encounters": ${NEW_ENCOUNTERS:-0}
    },
    "content_analysis": {
        "fall_content_found": $FALL_CONTENT_FOUND,
        "keywords_found": "$KEYWORDS_FOUND_ESCAPED",
        "score_documented": $SCORE_FOUND,
        "intervention_documented": $INTERVENTION_FOUND
    },
    "newest_note_body": "$NEWEST_NOTE_BODY_ESCAPED",
    "screenshot_exists": $([ -f "/tmp/task_final_state.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result with proper permissions
rm -f /tmp/fall_risk_result.json 2>/dev/null || sudo rm -f /tmp/fall_risk_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/fall_risk_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/fall_risk_result.json
chmod 666 /tmp/fall_risk_result.json 2>/dev/null || sudo chmod 666 /tmp/fall_risk_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/fall_risk_result.json"
cat /tmp/fall_risk_result.json
echo ""
echo "=== Export Complete ==="
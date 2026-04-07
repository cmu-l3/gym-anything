#!/bin/bash
# Export script for Record Telephone Encounter Task

echo "=== Exporting Record Telephone Encounter Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot first
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png
if [ -f /tmp/task_final.png ]; then
    SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Target patient
PATIENT_PID=3

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial counts
INITIAL_ENCOUNTER_COUNT=$(cat /tmp/initial_encounter_count.txt 2>/dev/null || echo "0")
HIGHEST_ENCOUNTER_ID=$(cat /tmp/highest_encounter_id.txt 2>/dev/null || echo "0")

# Get current encounter count
CURRENT_ENCOUNTER_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo "Encounter count: initial=$INITIAL_ENCOUNTER_COUNT, current=$CURRENT_ENCOUNTER_COUNT"

# Get today's date
TODAY=$(date +%Y-%m-%d)

# Query for new encounters for this patient (id > highest_encounter_id)
echo ""
echo "=== Querying encounters for patient PID=$PATIENT_PID ==="

# Get all recent encounters
ALL_ENCOUNTERS=$(openemr_query "SELECT id, date, reason, pc_catid, sensitivity FROM form_encounter WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 10" 2>/dev/null)
echo "Recent encounters for patient:"
echo "$ALL_ENCOUNTERS"

# Find new encounters (created after task started)
NEW_ENCOUNTER=$(openemr_query "SELECT id, date, reason, pc_catid, sensitivity FROM form_encounter WHERE pid=$PATIENT_PID AND id > $HIGHEST_ENCOUNTER_ID ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Parse encounter data
ENCOUNTER_FOUND="false"
ENCOUNTER_ID=""
ENCOUNTER_DATE=""
ENCOUNTER_REASON=""
ENCOUNTER_CATID=""
ENCOUNTER_SENSITIVITY=""

if [ -n "$NEW_ENCOUNTER" ]; then
    ENCOUNTER_FOUND="true"
    ENCOUNTER_ID=$(echo "$NEW_ENCOUNTER" | cut -f1)
    ENCOUNTER_DATE=$(echo "$NEW_ENCOUNTER" | cut -f2)
    ENCOUNTER_REASON=$(echo "$NEW_ENCOUNTER" | cut -f3)
    ENCOUNTER_CATID=$(echo "$NEW_ENCOUNTER" | cut -f4)
    ENCOUNTER_SENSITIVITY=$(echo "$NEW_ENCOUNTER" | cut -f5)
    
    echo ""
    echo "New encounter found:"
    echo "  ID: $ENCOUNTER_ID"
    echo "  Date: $ENCOUNTER_DATE"
    echo "  Reason: $ENCOUNTER_REASON"
    echo "  Category ID: $ENCOUNTER_CATID"
else
    echo "No new encounter found for patient"
fi

# Get category name if we have a category ID
CATEGORY_NAME=""
if [ -n "$ENCOUNTER_CATID" ] && [ "$ENCOUNTER_CATID" != "NULL" ]; then
    CATEGORY_NAME=$(openemr_query "SELECT pc_catname FROM openemr_postcalendar_categories WHERE pc_catid=$ENCOUNTER_CATID" 2>/dev/null || echo "")
    echo "  Category Name: $CATEGORY_NAME"
fi

# Check if category indicates phone call
IS_PHONE_CATEGORY="false"
CATEGORY_LOWER=$(echo "$CATEGORY_NAME" | tr '[:upper:]' '[:lower:]')
if echo "$CATEGORY_LOWER" | grep -qE "(phone|telephone|call|tele)"; then
    IS_PHONE_CATEGORY="true"
    echo "Category indicates phone call: YES"
else
    echo "Category indicates phone call: NO (category='$CATEGORY_NAME')"
fi

# Check if reason contains appropriate keywords
REASON_HAS_KEYWORDS="false"
REASON_LOWER=$(echo "$ENCOUNTER_REASON" | tr '[:upper:]' '[:lower:]')
if echo "$REASON_LOWER" | grep -qE "(phone|telephone|call|dizziness|dizzy|orthostatic)"; then
    REASON_HAS_KEYWORDS="true"
    echo "Reason contains appropriate keywords: YES"
else
    echo "Reason contains appropriate keywords: NO"
fi

# Check if encounter date is today
DATE_IS_TODAY="false"
if [ "$ENCOUNTER_DATE" = "$TODAY" ]; then
    DATE_IS_TODAY="true"
    echo "Encounter date is today: YES"
else
    echo "Encounter date is today: NO (date='$ENCOUNTER_DATE', today='$TODAY')"
fi

# Check for associated forms/notes
ASSOCIATED_FORMS=""
if [ -n "$ENCOUNTER_ID" ]; then
    ASSOCIATED_FORMS=$(openemr_query "SELECT form_id, formdir, form_name FROM forms WHERE pid=$PATIENT_PID AND encounter=$ENCOUNTER_ID AND deleted=0" 2>/dev/null || echo "")
    if [ -n "$ASSOCIATED_FORMS" ]; then
        echo ""
        echo "Associated forms:"
        echo "$ASSOCIATED_FORMS"
    fi
fi

# Check for SOAP notes or other clinical notes
CLINICAL_NOTES=""
if [ -n "$ENCOUNTER_ID" ]; then
    # Try to get SOAP notes
    SOAP_NOTES=$(openemr_query "SELECT id, subjective, objective, assessment, plan FROM form_soap WHERE pid=$PATIENT_PID AND encounter=$ENCOUNTER_ID LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$SOAP_NOTES" ]; then
        CLINICAL_NOTES="$SOAP_NOTES"
        echo ""
        echo "SOAP notes found"
    fi
fi

# Escape special characters for JSON
ENCOUNTER_REASON_ESCAPED=$(echo "$ENCOUNTER_REASON" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)
CATEGORY_NAME_ESCAPED=$(echo "$CATEGORY_NAME" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/telephone_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_encounter_count": ${INITIAL_ENCOUNTER_COUNT:-0},
    "current_encounter_count": ${CURRENT_ENCOUNTER_COUNT:-0},
    "highest_previous_encounter_id": ${HIGHEST_ENCOUNTER_ID:-0},
    "new_encounter_found": $ENCOUNTER_FOUND,
    "encounter": {
        "id": "$ENCOUNTER_ID",
        "date": "$ENCOUNTER_DATE",
        "reason": "$ENCOUNTER_REASON_ESCAPED",
        "category_id": "$ENCOUNTER_CATID",
        "category_name": "$CATEGORY_NAME_ESCAPED"
    },
    "validation": {
        "is_phone_category": $IS_PHONE_CATEGORY,
        "reason_has_keywords": $REASON_HAS_KEYWORDS,
        "date_is_today": $DATE_IS_TODAY,
        "has_associated_forms": $([ -n "$ASSOCIATED_FORMS" ] && echo "true" || echo "false")
    },
    "today_date": "$TODAY",
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result JSON
rm -f /tmp/telephone_encounter_result.json 2>/dev/null || sudo rm -f /tmp/telephone_encounter_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/telephone_encounter_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/telephone_encounter_result.json
chmod 666 /tmp/telephone_encounter_result.json 2>/dev/null || sudo chmod 666 /tmp/telephone_encounter_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/telephone_encounter_result.json"
cat /tmp/telephone_encounter_result.json

echo ""
echo "=== Export Complete ==="
#!/bin/bash
# Export script for Document Advance Directive task
# Exports all relevant data for verification

echo "=== Exporting Document Advance Directive Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png
echo "Final screenshot saved to /tmp/task_final_state.png"

# Target patient
PATIENT_PID=5

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial state values
INITIAL_AD_REVIEWED=$(cat /tmp/initial_ad_reviewed.txt 2>/dev/null || echo "")
INITIAL_NOTES_COUNT=$(cat /tmp/initial_notes_count.txt 2>/dev/null || echo "0")
INITIAL_HISTORY_COUNT=$(cat /tmp/initial_history_count.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"
echo "Initial notes count: $INITIAL_NOTES_COUNT"

# Query current patient data
echo ""
echo "=== Querying current patient state ==="

# Get patient basic info
PATIENT_INFO=$(openemr_query "SELECT pid, fname, lname, DOB FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "")
echo "Patient info: $PATIENT_INFO"

# Get advance directive fields from patient_data
AD_DATA=$(openemr_query "SELECT IFNULL(ad_reviewed,'NULL') as ad_reviewed, IFNULL(usertext1,'') as ut1, IFNULL(usertext2,'') as ut2, IFNULL(usertext3,'') as ut3, IFNULL(usertext4,'') as ut4, IFNULL(usertext5,'') as ut5, IFNULL(usertext6,'') as ut6, IFNULL(usertext7,'') as ut7, IFNULL(usertext8,'') as ut8 FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "")
echo "AD data from patient_data: $AD_DATA"

# Parse AD data
AD_REVIEWED=$(echo "$AD_DATA" | cut -f1)
USERTEXT1=$(echo "$AD_DATA" | cut -f2)
USERTEXT2=$(echo "$AD_DATA" | cut -f3)
USERTEXT3=$(echo "$AD_DATA" | cut -f4)
USERTEXT4=$(echo "$AD_DATA" | cut -f5)
USERTEXT5=$(echo "$AD_DATA" | cut -f6)
USERTEXT6=$(echo "$AD_DATA" | cut -f7)
USERTEXT7=$(echo "$AD_DATA" | cut -f8)
USERTEXT8=$(echo "$AD_DATA" | cut -f9)

# Check if ad_reviewed was updated
AD_STATUS_UPDATED="false"
if [ -n "$AD_REVIEWED" ] && [ "$AD_REVIEWED" != "NULL" ] && [ "$AD_REVIEWED" != "0000-00-00" ] && [ "$AD_REVIEWED" != "$INITIAL_AD_REVIEWED" ]; then
    AD_STATUS_UPDATED="true"
    echo "AD reviewed date updated: $AD_REVIEWED"
fi

# Get current notes count and check for new notes
CURRENT_NOTES_COUNT=$(openemr_query "SELECT COUNT(*) FROM pnotes WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "Current notes count: $CURRENT_NOTES_COUNT (was $INITIAL_NOTES_COUNT)"

NEW_NOTES_ADDED="false"
if [ "$CURRENT_NOTES_COUNT" -gt "$INITIAL_NOTES_COUNT" ]; then
    NEW_NOTES_ADDED="true"
fi

# Get recent notes content that might contain AD info
RECENT_NOTES=$(openemr_query "SELECT id, body FROM pnotes WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 5" 2>/dev/null || echo "")
echo "Recent notes: $RECENT_NOTES"

# Get history_data for this patient
CURRENT_HISTORY_COUNT=$(openemr_query "SELECT COUNT(*) FROM history_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
HISTORY_DATA=$(openemr_query "SELECT IFNULL(usertext11,'') as ut11, IFNULL(usertext12,'') as ut12, IFNULL(usertext13,'') as ut13, IFNULL(usertext14,'') as ut14, IFNULL(usertext15,'') as ut15 FROM history_data WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
echo "History data: $HISTORY_DATA"

# Combine all text fields for content search
ALL_TEXT="$USERTEXT1 $USERTEXT2 $USERTEXT3 $USERTEXT4 $USERTEXT5 $USERTEXT6 $USERTEXT7 $USERTEXT8 $HISTORY_DATA $RECENT_NOTES"
ALL_TEXT_LOWER=$(echo "$ALL_TEXT" | tr '[:upper:]' '[:lower:]')

# Check for proxy name (Margaret Ledner)
PROXY_NAME_FOUND="false"
if echo "$ALL_TEXT_LOWER" | grep -qi "margaret"; then
    PROXY_NAME_FOUND="true"
    echo "Proxy name 'Margaret' found in records"
fi

# Check for phone number (555-123-4567 in any format)
PROXY_PHONE_FOUND="false"
ALL_TEXT_DIGITS=$(echo "$ALL_TEXT" | tr -cd '0-9')
if echo "$ALL_TEXT_DIGITS" | grep -q "5551234567"; then
    PROXY_PHONE_FOUND="true"
    echo "Proxy phone found in records"
fi

# Check for document type mentions
DOC_TYPES_FOUND="false"
if echo "$ALL_TEXT_LOWER" | grep -qiE "(molst|polst|healthcare proxy|advance directive|living will)"; then
    DOC_TYPES_FOUND="true"
    echo "Document type keywords found"
fi

# Check for DNR/clinical preference mentions
CLINICAL_PREFS_FOUND="false"
if echo "$ALL_TEXT_LOWER" | grep -qiE "(dnr|dni|do not resuscitate|comfort measures|comfort care)"; then
    CLINICAL_PREFS_FOUND="true"
    echo "Clinical preference keywords found"
fi

# Escape special characters for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr '\n' ' ' | sed 's/\t/ /g'
}

USERTEXT1_ESC=$(escape_json "$USERTEXT1")
USERTEXT2_ESC=$(escape_json "$USERTEXT2")
USERTEXT3_ESC=$(escape_json "$USERTEXT3")
USERTEXT4_ESC=$(escape_json "$USERTEXT4")
RECENT_NOTES_ESC=$(escape_json "$RECENT_NOTES")
HISTORY_DATA_ESC=$(escape_json "$HISTORY_DATA")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/ad_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_state": {
        "ad_reviewed": "$INITIAL_AD_REVIEWED",
        "notes_count": $INITIAL_NOTES_COUNT,
        "history_count": $INITIAL_HISTORY_COUNT
    },
    "current_state": {
        "ad_reviewed": "$AD_REVIEWED",
        "notes_count": $CURRENT_NOTES_COUNT,
        "history_count": $CURRENT_HISTORY_COUNT,
        "usertext1": "$USERTEXT1_ESC",
        "usertext2": "$USERTEXT2_ESC",
        "usertext3": "$USERTEXT3_ESC",
        "usertext4": "$USERTEXT4_ESC",
        "recent_notes": "$RECENT_NOTES_ESC",
        "history_data": "$HISTORY_DATA_ESC"
    },
    "verification_flags": {
        "ad_status_updated": $AD_STATUS_UPDATED,
        "new_notes_added": $NEW_NOTES_ADDED,
        "proxy_name_found": $PROXY_NAME_FOUND,
        "proxy_phone_found": $PROXY_PHONE_FOUND,
        "document_types_found": $DOC_TYPES_FOUND,
        "clinical_prefs_found": $CLINICAL_PREFS_FOUND
    },
    "screenshot_exists": $([ -f "/tmp/task_final_state.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/advance_directive_result.json 2>/dev/null || sudo rm -f /tmp/advance_directive_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/advance_directive_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/advance_directive_result.json
chmod 666 /tmp/advance_directive_result.json 2>/dev/null || sudo chmod 666 /tmp/advance_directive_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/advance_directive_result.json"
cat /tmp/advance_directive_result.json
echo ""
echo "=== Export Complete ==="
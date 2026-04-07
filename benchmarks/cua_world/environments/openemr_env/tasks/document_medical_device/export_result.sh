#!/bin/bash
# Export script for Document Medical Device Task

echo "=== Exporting Document Medical Device Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final_state.png

# Target patient
PATIENT_PID=3

# Get initial state values
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_DEVICE_COUNT=$(cat /tmp/initial_device_count.txt 2>/dev/null || echo "0")
INITIAL_LISTS_COUNT=$(cat /tmp/initial_lists_count.txt 2>/dev/null || echo "0")
INITIAL_MAX_LIST_ID=$(cat /tmp/initial_max_list_id.txt 2>/dev/null || echo "0")

echo "Task start timestamp: $TASK_START"
echo "Initial device count: $INITIAL_DEVICE_COUNT"
echo "Initial lists count: $INITIAL_LISTS_COUNT"
echo "Initial max list ID: $INITIAL_MAX_LIST_ID"

# Get current counts
CURRENT_DEVICE_COUNT=$(openemr_query "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND (LOWER(title) LIKE '%pacemaker%' OR LOWER(title) LIKE '%implant%' OR LOWER(title) LIKE '%device%' OR LOWER(comments) LIKE '%medtronic%' OR LOWER(comments) LIKE '%pjn847291%')" 2>/dev/null || echo "0")
CURRENT_LISTS_COUNT=$(openemr_query "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_MAX_LIST_ID=$(openemr_query "SELECT COALESCE(MAX(id), 0) FROM lists" 2>/dev/null || echo "0")

echo "Current device count: $CURRENT_DEVICE_COUNT"
echo "Current lists count: $CURRENT_LISTS_COUNT"
echo "Current max list ID: $CURRENT_MAX_LIST_ID"

# Query for device-related entries added for this patient
echo ""
echo "=== Searching for device entries for patient PID=$PATIENT_PID ==="

# Search with multiple patterns to find the pacemaker entry
DEVICE_ENTRY=$(openemr_query "SELECT id, pid, type, title, begdate, diagnosis, comments, date FROM lists WHERE pid=$PATIENT_PID AND id > $INITIAL_MAX_LIST_ID AND (LOWER(title) LIKE '%pacemaker%' OR LOWER(title) LIKE '%cardiac%' OR LOWER(title) LIKE '%medtronic%' OR LOWER(title) LIKE '%implant%' OR LOWER(title) LIKE '%device%' OR LOWER(comments) LIKE '%pacemaker%' OR LOWER(comments) LIKE '%medtronic%' OR LOWER(comments) LIKE '%pjn847291%' OR LOWER(comments) LIKE '%azure%') ORDER BY id DESC LIMIT 1" 2>/dev/null)

# If no specific device entry found, check for ANY new entry
if [ -z "$DEVICE_ENTRY" ]; then
    echo "No specific device entry found, checking for any new list entry..."
    DEVICE_ENTRY=$(openemr_query "SELECT id, pid, type, title, begdate, diagnosis, comments, date FROM lists WHERE pid=$PATIENT_PID AND id > $INITIAL_MAX_LIST_ID ORDER BY id DESC LIMIT 1" 2>/dev/null)
fi

# Parse device entry data
ENTRY_FOUND="false"
ENTRY_ID=""
ENTRY_TYPE=""
ENTRY_TITLE=""
ENTRY_BEGDATE=""
ENTRY_DIAGNOSIS=""
ENTRY_COMMENTS=""
ENTRY_DATE=""

if [ -n "$DEVICE_ENTRY" ]; then
    ENTRY_FOUND="true"
    ENTRY_ID=$(echo "$DEVICE_ENTRY" | cut -f1)
    ENTRY_PID=$(echo "$DEVICE_ENTRY" | cut -f2)
    ENTRY_TYPE=$(echo "$DEVICE_ENTRY" | cut -f3)
    ENTRY_TITLE=$(echo "$DEVICE_ENTRY" | cut -f4)
    ENTRY_BEGDATE=$(echo "$DEVICE_ENTRY" | cut -f5)
    ENTRY_DIAGNOSIS=$(echo "$DEVICE_ENTRY" | cut -f6)
    ENTRY_COMMENTS=$(echo "$DEVICE_ENTRY" | cut -f7)
    ENTRY_DATE=$(echo "$DEVICE_ENTRY" | cut -f8)

    echo ""
    echo "Device entry found:"
    echo "  ID: $ENTRY_ID"
    echo "  Type: $ENTRY_TYPE"
    echo "  Title: $ENTRY_TITLE"
    echo "  Begin Date: $ENTRY_BEGDATE"
    echo "  Diagnosis: $ENTRY_DIAGNOSIS"
    echo "  Comments: $ENTRY_COMMENTS"
    echo "  Created: $ENTRY_DATE"
else
    echo "No new entry found for patient"
fi

# Check for specific content in title and comments
COMBINED_TEXT=$(echo "$ENTRY_TITLE $ENTRY_COMMENTS $ENTRY_DIAGNOSIS" | tr '[:upper:]' '[:lower:]')

# Check for pacemaker mention
PACEMAKER_MENTIONED="false"
if echo "$COMBINED_TEXT" | grep -qE "(pacemaker|cardiac.*(device|implant)|pacer)"; then
    PACEMAKER_MENTIONED="true"
    echo "Pacemaker/cardiac device mentioned: YES"
else
    echo "Pacemaker/cardiac device mentioned: NO"
fi

# Check for Medtronic manufacturer
MEDTRONIC_MENTIONED="false"
if echo "$COMBINED_TEXT" | grep -qi "medtronic"; then
    MEDTRONIC_MENTIONED="true"
    echo "Medtronic manufacturer mentioned: YES"
else
    echo "Medtronic manufacturer mentioned: NO"
fi

# Check for model (Azure, SureScan)
MODEL_MENTIONED="false"
if echo "$COMBINED_TEXT" | grep -qiE "(azure|surescan)"; then
    MODEL_MENTIONED="true"
    echo "Model (Azure/SureScan) mentioned: YES"
else
    echo "Model (Azure/SureScan) mentioned: NO"
fi

# Check for serial number
SERIAL_MENTIONED="false"
if echo "$COMBINED_TEXT" | grep -qi "pjn847291"; then
    SERIAL_MENTIONED="true"
    echo "Serial number (PJN847291) mentioned: YES"
else
    echo "Serial number (PJN847291) mentioned: NO"
fi

# Check for correct implant date
DATE_CORRECT="false"
if [ "$ENTRY_BEGDATE" = "2024-09-15" ]; then
    DATE_CORRECT="true"
    echo "Implant date correct (2024-09-15): YES"
else
    echo "Implant date correct: NO (got: $ENTRY_BEGDATE)"
fi

# Check for MRI status mention
MRI_MENTIONED="false"
if echo "$COMBINED_TEXT" | grep -qiE "(mri|magnetic)"; then
    MRI_MENTIONED="true"
    echo "MRI status mentioned: YES"
else
    echo "MRI status mentioned: NO"
fi

# Check if entry was created after task start (anti-gaming)
CREATED_DURING_TASK="false"
if [ -n "$ENTRY_DATE" ]; then
    # Try to convert entry date to epoch
    ENTRY_EPOCH=$(date -d "$ENTRY_DATE" +%s 2>/dev/null || echo "0")
    if [ "$ENTRY_EPOCH" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
        echo "Entry created during task: YES"
    else
        echo "Entry created during task: NO (may be pre-existing)"
    fi
fi

# Also check if list ID is higher than initial (secondary check)
NEW_ENTRY_BY_ID="false"
if [ -n "$ENTRY_ID" ] && [ "$ENTRY_ID" -gt "$INITIAL_MAX_LIST_ID" ]; then
    NEW_ENTRY_BY_ID="true"
fi

# Escape special characters for JSON
ENTRY_TITLE_ESCAPED=$(echo "$ENTRY_TITLE" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)
ENTRY_COMMENTS_ESCAPED=$(echo "$ENTRY_COMMENTS" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 1000)
ENTRY_DIAGNOSIS_ESCAPED=$(echo "$ENTRY_DIAGNOSIS" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)

# Create result JSON
TEMP_JSON=$(mktemp /tmp/device_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "initial_device_count": ${INITIAL_DEVICE_COUNT:-0},
    "current_device_count": ${CURRENT_DEVICE_COUNT:-0},
    "initial_lists_count": ${INITIAL_LISTS_COUNT:-0},
    "current_lists_count": ${CURRENT_LISTS_COUNT:-0},
    "initial_max_list_id": ${INITIAL_MAX_LIST_ID:-0},
    "current_max_list_id": ${CURRENT_MAX_LIST_ID:-0},
    "entry_found": $ENTRY_FOUND,
    "entry": {
        "id": "$ENTRY_ID",
        "type": "$ENTRY_TYPE",
        "title": "$ENTRY_TITLE_ESCAPED",
        "begdate": "$ENTRY_BEGDATE",
        "diagnosis": "$ENTRY_DIAGNOSIS_ESCAPED",
        "comments": "$ENTRY_COMMENTS_ESCAPED",
        "created_date": "$ENTRY_DATE"
    },
    "validation": {
        "pacemaker_mentioned": $PACEMAKER_MENTIONED,
        "medtronic_mentioned": $MEDTRONIC_MENTIONED,
        "model_mentioned": $MODEL_MENTIONED,
        "serial_mentioned": $SERIAL_MENTIONED,
        "date_correct": $DATE_CORRECT,
        "mri_mentioned": $MRI_MENTIONED,
        "created_during_task": $CREATED_DURING_TASK,
        "new_entry_by_id": $NEW_ENTRY_BY_ID
    },
    "screenshot_exists": $([ -f "/tmp/task_final_state.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result with proper permissions
rm -f /tmp/document_device_result.json 2>/dev/null || sudo rm -f /tmp/document_device_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/document_device_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/document_device_result.json
chmod 666 /tmp/document_device_result.json 2>/dev/null || sudo chmod 666 /tmp/document_device_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/document_device_result.json"
cat /tmp/document_device_result.json

echo ""
echo "=== Export Complete ==="
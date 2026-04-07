#!/bin/bash
# Export script for Add Patient Safety Alert Task

echo "=== Exporting Patient Safety Alert Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot saved to /tmp/task_final.png"

# Target patient
PATIENT_PID=4

# Get timestamps and initial counts
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_ALERT_COUNT=$(cat /tmp/initial_alert_count.txt 2>/dev/null || echo "0")
INITIAL_LISTS_COUNT=$(cat /tmp/initial_lists_count.txt 2>/dev/null || echo "0")
EXISTING_VENIPUNCTURE=$(cat /tmp/existing_venipuncture_alert.txt 2>/dev/null || echo "")

# Get current counts
CURRENT_ALERT_COUNT=$(openemr_query "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND (type='alert' OR type='warning' OR type='flag' OR (type='medical_problem' AND title LIKE '%alert%'))" 2>/dev/null || echo "0")
CURRENT_LISTS_COUNT=$(openemr_query "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo "Alert count: initial=$INITIAL_ALERT_COUNT, current=$CURRENT_ALERT_COUNT"
echo "Total lists count: initial=$INITIAL_LISTS_COUNT, current=$CURRENT_LISTS_COUNT"

# Query for any new entries that might be alerts (broad search)
echo ""
echo "=== Searching for new alert entries ==="

# Search for venipuncture/IV access related entries
VENIPUNCTURE_ENTRIES=$(openemr_query "SELECT id, pid, type, title, comments, date, activity FROM lists WHERE pid=$PATIENT_PID AND (LOWER(title) LIKE '%venipuncture%' OR LOWER(title) LIKE '%iv%' OR LOWER(title) LIKE '%access%' OR LOWER(title) LIKE '%needle%' OR LOWER(title) LIKE '%vein%' OR LOWER(title) LIKE '%phlebotom%' OR LOWER(comments) LIKE '%venipuncture%' OR LOWER(comments) LIKE '%scar%') ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "Venipuncture-related entries:"
echo "$VENIPUNCTURE_ENTRIES"

# Search for any alert/warning type entries
ALERT_ENTRIES=$(openemr_query "SELECT id, pid, type, title, comments, date, activity FROM lists WHERE pid=$PATIENT_PID AND (type='alert' OR type='warning' OR type='flag') ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo ""
echo "Alert/warning type entries:"
echo "$ALERT_ENTRIES"

# Get the most recent entry for this patient (newest by id)
NEWEST_ENTRY=$(openemr_query "SELECT id, pid, type, title, comments, date, activity FROM lists WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
echo ""
echo "Most recent list entry for patient:"
echo "$NEWEST_ENTRY"

# Parse the best matching alert
ALERT_FOUND="false"
ALERT_ID=""
ALERT_TYPE=""
ALERT_TITLE=""
ALERT_COMMENTS=""
ALERT_DATE=""
ALERT_ACTIVITY=""
ALERT_HAS_VENIPUNCTURE_KEYWORD="false"
ALERT_HAS_CLINICAL_DETAIL="false"

# First, try to find venipuncture-specific entry
if [ -n "$VENIPUNCTURE_ENTRIES" ]; then
    ALERT_FOUND="true"
    # Parse first line (most recent)
    FIRST_LINE=$(echo "$VENIPUNCTURE_ENTRIES" | head -1)
    ALERT_ID=$(echo "$FIRST_LINE" | cut -f1)
    ALERT_PID=$(echo "$FIRST_LINE" | cut -f2)
    ALERT_TYPE=$(echo "$FIRST_LINE" | cut -f3)
    ALERT_TITLE=$(echo "$FIRST_LINE" | cut -f4)
    ALERT_COMMENTS=$(echo "$FIRST_LINE" | cut -f5)
    ALERT_DATE=$(echo "$FIRST_LINE" | cut -f6)
    ALERT_ACTIVITY=$(echo "$FIRST_LINE" | cut -f7)
    
    echo ""
    echo "Found venipuncture-related alert:"
    echo "  ID: $ALERT_ID"
    echo "  Type: $ALERT_TYPE"
    echo "  Title: $ALERT_TITLE"
    echo "  Comments: $ALERT_COMMENTS"
    echo "  Date: $ALERT_DATE"
    echo "  Activity: $ALERT_ACTIVITY"
# If no venipuncture entry, check for any new alert-type entry
elif [ -n "$ALERT_ENTRIES" ] && [ "$CURRENT_ALERT_COUNT" -gt "$INITIAL_ALERT_COUNT" ]; then
    ALERT_FOUND="true"
    FIRST_LINE=$(echo "$ALERT_ENTRIES" | head -1)
    ALERT_ID=$(echo "$FIRST_LINE" | cut -f1)
    ALERT_TYPE=$(echo "$FIRST_LINE" | cut -f3)
    ALERT_TITLE=$(echo "$FIRST_LINE" | cut -f4)
    ALERT_COMMENTS=$(echo "$FIRST_LINE" | cut -f5)
    ALERT_DATE=$(echo "$FIRST_LINE" | cut -f6)
    ALERT_ACTIVITY=$(echo "$FIRST_LINE" | cut -f7)
    
    echo ""
    echo "Found new alert-type entry:"
    echo "  ID: $ALERT_ID"
    echo "  Type: $ALERT_TYPE"
    echo "  Title: $ALERT_TITLE"
# Check if any new list entry was added
elif [ "$CURRENT_LISTS_COUNT" -gt "$INITIAL_LISTS_COUNT" ] && [ -n "$NEWEST_ENTRY" ]; then
    ALERT_FOUND="true"
    FIRST_LINE=$(echo "$NEWEST_ENTRY" | head -1)
    ALERT_ID=$(echo "$FIRST_LINE" | cut -f1)
    ALERT_TYPE=$(echo "$FIRST_LINE" | cut -f3)
    ALERT_TITLE=$(echo "$FIRST_LINE" | cut -f4)
    ALERT_COMMENTS=$(echo "$FIRST_LINE" | cut -f5)
    ALERT_DATE=$(echo "$FIRST_LINE" | cut -f6)
    ALERT_ACTIVITY=$(echo "$FIRST_LINE" | cut -f7)
    
    echo ""
    echo "Found new list entry (may be alert):"
    echo "  ID: $ALERT_ID"
    echo "  Type: $ALERT_TYPE"
    echo "  Title: $ALERT_TITLE"
else
    echo ""
    echo "No new alert found for patient"
fi

# Check for venipuncture keywords in title or comments
COMBINED_TEXT=$(echo "$ALERT_TITLE $ALERT_COMMENTS" | tr '[:upper:]' '[:lower:]')
if echo "$COMBINED_TEXT" | grep -qiE "(venipuncture|iv.?access|difficult.?iv|needle|vein|phlebotom)"; then
    ALERT_HAS_VENIPUNCTURE_KEYWORD="true"
fi

# Check for clinical detail keywords
if echo "$COMBINED_TEXT" | grep -qiE "(scar|butterfly|hand|arm|dorsum|bilateral|experienced|recommend)"; then
    ALERT_HAS_CLINICAL_DETAIL="true"
fi

# Check if alert is active (activity = 1 or empty which often means active)
ALERT_IS_ACTIVE="false"
if [ "$ALERT_ACTIVITY" = "1" ] || [ -z "$ALERT_ACTIVITY" ]; then
    ALERT_IS_ACTIVE="true"
fi

# Escape special characters for JSON
ALERT_TITLE_ESC=$(echo "$ALERT_TITLE" | sed 's/"/\\"/g' | tr '\n' ' ' | tr '\r' ' ')
ALERT_COMMENTS_ESC=$(echo "$ALERT_COMMENTS" | sed 's/"/\\"/g' | tr '\n' ' ' | tr '\r' ' ')
EXISTING_VENIPUNCTURE_ESC=$(echo "$EXISTING_VENIPUNCTURE" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/alert_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "initial_alert_count": ${INITIAL_ALERT_COUNT:-0},
    "current_alert_count": ${CURRENT_ALERT_COUNT:-0},
    "initial_lists_count": ${INITIAL_LISTS_COUNT:-0},
    "current_lists_count": ${CURRENT_LISTS_COUNT:-0},
    "existing_venipuncture_alert": "$EXISTING_VENIPUNCTURE_ESC",
    "alert_found": $ALERT_FOUND,
    "alert": {
        "id": "$ALERT_ID",
        "type": "$ALERT_TYPE",
        "title": "$ALERT_TITLE_ESC",
        "comments": "$ALERT_COMMENTS_ESC",
        "date": "$ALERT_DATE",
        "activity": "$ALERT_ACTIVITY"
    },
    "validation": {
        "has_venipuncture_keyword": $ALERT_HAS_VENIPUNCTURE_KEYWORD,
        "has_clinical_detail": $ALERT_HAS_CLINICAL_DETAIL,
        "is_active": $ALERT_IS_ACTIVE,
        "new_entry_added": $([ "$CURRENT_LISTS_COUNT" -gt "$INITIAL_LISTS_COUNT" ] && echo "true" || echo "false")
    },
    "screenshot_path": "/tmp/task_final.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/patient_alert_result.json 2>/dev/null || sudo rm -f /tmp/patient_alert_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/patient_alert_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/patient_alert_result.json
chmod 666 /tmp/patient_alert_result.json 2>/dev/null || sudo chmod 666 /tmp/patient_alert_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/patient_alert_result.json"
cat /tmp/patient_alert_result.json
echo ""
echo "=== Export Complete ==="
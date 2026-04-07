#!/bin/bash
# Export script for Record Patient Disclosure Task

echo "=== Exporting Record Patient Disclosure Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png

# Target patient
PATIENT_PID=5

# Get timestamps and initial counts
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_DISCLOSURE_COUNT=$(cat /tmp/initial_disclosure_count.txt 2>/dev/null || echo "0")
INITIAL_DISCLOSURE_TABLE_COUNT=$(cat /tmp/initial_disclosure_table_count.txt 2>/dev/null || echo "0")

echo "Task timing: start=$TASK_START, end=$TASK_END"
echo "Initial disclosure count: $INITIAL_DISCLOSURE_COUNT"

# Query for new disclosures in extended_log
echo ""
echo "=== Querying extended_log for new disclosures ==="
CURRENT_DISCLOSURE_COUNT=$(openemr_query "SELECT COUNT(*) FROM extended_log WHERE patient_id=$PATIENT_PID AND event LIKE '%disclosure%'" 2>/dev/null || echo "0")
echo "Current disclosure count (extended_log): $CURRENT_DISCLOSURE_COUNT"

# Get all disclosure entries for patient (newest first)
ALL_DISCLOSURES=$(openemr_query "SELECT id, date, event, recipient, comments FROM extended_log WHERE patient_id=$PATIENT_PID AND event LIKE '%disclosure%' ORDER BY id DESC LIMIT 10" 2>/dev/null)
echo "All disclosures for patient:"
echo "$ALL_DISCLOSURES"

# Get the newest disclosure entry (if any new ones were added)
NEWEST_DISCLOSURE=""
DISCLOSURE_FOUND="false"
DISCLOSURE_ID=""
DISCLOSURE_DATE=""
DISCLOSURE_EVENT=""
DISCLOSURE_RECIPIENT=""
DISCLOSURE_COMMENTS=""

if [ "$CURRENT_DISCLOSURE_COUNT" -gt "$INITIAL_DISCLOSURE_COUNT" ]; then
    echo "New disclosure(s) detected in extended_log!"
    NEWEST_DISCLOSURE=$(openemr_query "SELECT id, date, event, recipient, comments FROM extended_log WHERE patient_id=$PATIENT_PID AND event LIKE '%disclosure%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$NEWEST_DISCLOSURE" ]; then
        DISCLOSURE_FOUND="true"
        DISCLOSURE_ID=$(echo "$NEWEST_DISCLOSURE" | cut -f1)
        DISCLOSURE_DATE=$(echo "$NEWEST_DISCLOSURE" | cut -f2)
        DISCLOSURE_EVENT=$(echo "$NEWEST_DISCLOSURE" | cut -f3)
        DISCLOSURE_RECIPIENT=$(echo "$NEWEST_DISCLOSURE" | cut -f4)
        DISCLOSURE_COMMENTS=$(echo "$NEWEST_DISCLOSURE" | cut -f5)
        
        echo "Newest disclosure:"
        echo "  ID: $DISCLOSURE_ID"
        echo "  Date: $DISCLOSURE_DATE"
        echo "  Event: $DISCLOSURE_EVENT"
        echo "  Recipient: $DISCLOSURE_RECIPIENT"
        echo "  Comments: $DISCLOSURE_COMMENTS"
    fi
fi

# Also check dedicated disclosure table if it exists
DISCLOSURE_TABLE_EXISTS=$(openemr_query "SHOW TABLES LIKE 'disclosure'" 2>/dev/null || echo "")
CURRENT_DISCLOSURE_TABLE_COUNT="0"
DISCLOSURE_TABLE_DATA=""

if [ -n "$DISCLOSURE_TABLE_EXISTS" ]; then
    echo ""
    echo "=== Checking dedicated disclosure table ==="
    CURRENT_DISCLOSURE_TABLE_COUNT=$(openemr_query "SELECT COUNT(*) FROM disclosure WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
    echo "Current count in disclosure table: $CURRENT_DISCLOSURE_TABLE_COUNT"
    
    if [ "$CURRENT_DISCLOSURE_TABLE_COUNT" -gt "$INITIAL_DISCLOSURE_TABLE_COUNT" ]; then
        echo "New disclosure(s) detected in disclosure table!"
        DISCLOSURE_TABLE_DATA=$(openemr_query "SELECT * FROM disclosure WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
        
        if [ -n "$DISCLOSURE_TABLE_DATA" ] && [ "$DISCLOSURE_FOUND" = "false" ]; then
            DISCLOSURE_FOUND="true"
            # Parse the disclosure table data (columns vary by OpenEMR version)
            DISCLOSURE_ID=$(echo "$DISCLOSURE_TABLE_DATA" | cut -f1)
            DISCLOSURE_RECIPIENT=$(echo "$DISCLOSURE_TABLE_DATA" | cut -f3)
            DISCLOSURE_COMMENTS=$(echo "$DISCLOSURE_TABLE_DATA" | cut -f4)
        fi
        echo "Disclosure table data: $DISCLOSURE_TABLE_DATA"
    fi
fi

# Check for any log entries containing disclosure keywords for this patient
echo ""
echo "=== Checking all log entries for disclosure activity ==="
RECENT_LOG_ENTRIES=$(openemr_query "SELECT id, date, event, user, patient_id, comments FROM log WHERE patient_id=$PATIENT_PID AND date >= FROM_UNIXTIME($TASK_START) ORDER BY id DESC LIMIT 20" 2>/dev/null || echo "")
echo "Recent log entries during task:"
echo "$RECENT_LOG_ENTRIES"

# Validate recipient contains expected keywords
RECIPIENT_VALID="false"
RECIPIENT_LOWER=$(echo "$DISCLOSURE_RECIPIENT" | tr '[:upper:]' '[:lower:]')
if echo "$RECIPIENT_LOWER" | grep -qE "(johnson|law|attorney|legal)"; then
    RECIPIENT_VALID="true"
    echo "Recipient contains expected keywords"
fi

# Validate comments contain expected content
COMMENTS_VALID="false"
COMMENTS_LOWER=$(echo "$DISCLOSURE_COMMENTS" | tr '[:upper:]' '[:lower:]')
if echo "$COMMENTS_LOWER" | grep -qE "(medical|record|authorization|patient|injury)"; then
    COMMENTS_VALID="true"
    echo "Comments contain expected keywords"
fi

# Check if comments are non-empty
COMMENTS_NONEMPTY="false"
if [ -n "$DISCLOSURE_COMMENTS" ] && [ "$DISCLOSURE_COMMENTS" != "NULL" ]; then
    COMMENTS_NONEMPTY="true"
fi

# Escape special characters for JSON
DISCLOSURE_RECIPIENT_ESCAPED=$(echo "$DISCLOSURE_RECIPIENT" | sed 's/"/\\"/g' | tr '\n' ' ')
DISCLOSURE_COMMENTS_ESCAPED=$(echo "$DISCLOSURE_COMMENTS" | sed 's/"/\\"/g' | tr '\n' ' ')
DISCLOSURE_EVENT_ESCAPED=$(echo "$DISCLOSURE_EVENT" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/disclosure_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_disclosure_count": ${INITIAL_DISCLOSURE_COUNT:-0},
    "current_disclosure_count": ${CURRENT_DISCLOSURE_COUNT:-0},
    "initial_disclosure_table_count": ${INITIAL_DISCLOSURE_TABLE_COUNT:-0},
    "current_disclosure_table_count": ${CURRENT_DISCLOSURE_TABLE_COUNT:-0},
    "disclosure_found": $DISCLOSURE_FOUND,
    "disclosure": {
        "id": "$DISCLOSURE_ID",
        "date": "$DISCLOSURE_DATE",
        "event": "$DISCLOSURE_EVENT_ESCAPED",
        "recipient": "$DISCLOSURE_RECIPIENT_ESCAPED",
        "comments": "$DISCLOSURE_COMMENTS_ESCAPED"
    },
    "validation": {
        "recipient_contains_keywords": $RECIPIENT_VALID,
        "comments_contain_keywords": $COMMENTS_VALID,
        "comments_nonempty": $COMMENTS_NONEMPTY
    },
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/disclosure_result.json 2>/dev/null || sudo rm -f /tmp/disclosure_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/disclosure_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/disclosure_result.json
chmod 666 /tmp/disclosure_result.json 2>/dev/null || sudo chmod 666 /tmp/disclosure_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/disclosure_result.json"
cat /tmp/disclosure_result.json

echo ""
echo "=== Export Complete ==="
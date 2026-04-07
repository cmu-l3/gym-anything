#!/bin/bash
# Export script for Document Surgical History Task
echo "=== Exporting Document Surgical History Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

# Target patient
PATIENT_PID=3

# Get task timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial count
INITIAL_SURGERY_COUNT=$(cat /tmp/initial_surgery_count.txt 2>/dev/null || echo "0")

# Get current surgical history count for patient
CURRENT_SURGERY_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND type='surgery'" 2>/dev/null || echo "0")

echo "Surgical history count: initial=$INITIAL_SURGERY_COUNT, current=$CURRENT_SURGERY_COUNT"

# Query all surgical history entries for this patient
echo ""
echo "=== All surgical history entries for patient PID=$PATIENT_PID ==="
ALL_SURGERIES=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT id, title, begdate, comments, UNIX_TIMESTAMP(date) as created_ts FROM lists WHERE pid=$PATIENT_PID AND type='surgery' ORDER BY id DESC" 2>/dev/null)
echo "$ALL_SURGERIES"

# Search specifically for appendectomy entry
echo ""
echo "=== Searching for appendectomy entry ==="
APPENDECTOMY_ENTRY=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT id, pid, title, begdate, comments, UNIX_TIMESTAMP(date) as created_ts FROM lists WHERE pid=$PATIENT_PID AND type='surgery' AND (LOWER(title) LIKE '%appendectomy%' OR LOWER(title) LIKE '%appendix%') ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Parse appendectomy data
ENTRY_FOUND="false"
ENTRY_ID=""
ENTRY_PID=""
ENTRY_TITLE=""
ENTRY_DATE=""
ENTRY_COMMENTS=""
ENTRY_CREATED_TS="0"

if [ -n "$APPENDECTOMY_ENTRY" ]; then
    ENTRY_FOUND="true"
    ENTRY_ID=$(echo "$APPENDECTOMY_ENTRY" | cut -f1)
    ENTRY_PID=$(echo "$APPENDECTOMY_ENTRY" | cut -f2)
    ENTRY_TITLE=$(echo "$APPENDECTOMY_ENTRY" | cut -f3)
    ENTRY_DATE=$(echo "$APPENDECTOMY_ENTRY" | cut -f4)
    ENTRY_COMMENTS=$(echo "$APPENDECTOMY_ENTRY" | cut -f5)
    ENTRY_CREATED_TS=$(echo "$APPENDECTOMY_ENTRY" | cut -f6)
    
    echo "Appendectomy entry found:"
    echo "  ID: $ENTRY_ID"
    echo "  Patient PID: $ENTRY_PID"
    echo "  Title: $ENTRY_TITLE"
    echo "  Date: $ENTRY_DATE"
    echo "  Comments: $ENTRY_COMMENTS"
    echo "  Created timestamp: $ENTRY_CREATED_TS"
else
    echo "No appendectomy entry found"
    
    # Check if any new surgery entry was added (even with different name)
    if [ "$CURRENT_SURGERY_COUNT" -gt "$INITIAL_SURGERY_COUNT" ]; then
        echo ""
        echo "Note: New surgery entries were added but none match 'appendectomy'"
        NEWEST_SURGERY=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
            "SELECT id, pid, title, begdate, comments, UNIX_TIMESTAMP(date) as created_ts FROM lists WHERE pid=$PATIENT_PID AND type='surgery' ORDER BY id DESC LIMIT 1" 2>/dev/null)
        echo "Newest surgery entry: $NEWEST_SURGERY"
    fi
fi

# Check if entry was created during task (anti-gaming)
CREATED_DURING_TASK="false"
if [ "$ENTRY_CREATED_TS" -gt "$TASK_START" ] 2>/dev/null; then
    CREATED_DURING_TASK="true"
    echo "Entry was created during task execution"
else
    echo "Entry was NOT created during task (may have existed before)"
fi

# Validate date matches expected (2015-03-22)
DATE_CORRECT="false"
if [ "$ENTRY_DATE" = "2015-03-22" ]; then
    DATE_CORRECT="true"
    echo "Date matches expected value: 2015-03-22"
else
    echo "Date mismatch: expected 2015-03-22, got $ENTRY_DATE"
fi

# Check if comments mention expected details
COMMENTS_VALID="false"
COMMENTS_LOWER=$(echo "$ENTRY_COMMENTS" | tr '[:upper:]' '[:lower:]')
if echo "$COMMENTS_LOWER" | grep -qE "(laparoscopic|springfield|uncomplicated|recovery)"; then
    COMMENTS_VALID="true"
    echo "Comments contain expected details"
fi

# Escape special characters for JSON
ENTRY_TITLE_ESCAPED=$(echo "$ENTRY_TITLE" | sed 's/"/\\"/g' | tr '\n' ' ')
ENTRY_COMMENTS_ESCAPED=$(echo "$ENTRY_COMMENTS" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)

# Check if screenshot was captured
SCREENSHOT_EXISTS="false"
if [ -f "/tmp/task_final_state.png" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: $SCREENSHOT_SIZE bytes"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/surgical_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "initial_surgery_count": ${INITIAL_SURGERY_COUNT:-0},
    "current_surgery_count": ${CURRENT_SURGERY_COUNT:-0},
    "appendectomy_found": $ENTRY_FOUND,
    "entry": {
        "id": "$ENTRY_ID",
        "pid": "$ENTRY_PID",
        "title": "$ENTRY_TITLE_ESCAPED",
        "procedure_date": "$ENTRY_DATE",
        "comments": "$ENTRY_COMMENTS_ESCAPED",
        "created_timestamp": $ENTRY_CREATED_TS
    },
    "validation": {
        "created_during_task": $CREATED_DURING_TASK,
        "date_correct": $DATE_CORRECT,
        "comments_valid": $COMMENTS_VALID
    },
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result JSON
rm -f /tmp/surgical_history_result.json 2>/dev/null || sudo rm -f /tmp/surgical_history_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/surgical_history_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/surgical_history_result.json
chmod 666 /tmp/surgical_history_result.json 2>/dev/null || sudo chmod 666 /tmp/surgical_history_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/surgical_history_result.json"
cat /tmp/surgical_history_result.json

echo ""
echo "=== Export Complete ==="
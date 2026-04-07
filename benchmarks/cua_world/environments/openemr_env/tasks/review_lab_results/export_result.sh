#!/bin/bash
# Export script for Review Lab Results task

echo "=== Exporting Review Lab Results Task Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Target patient and order
PATIENT_PID=4
PROCEDURE_ORDER_ID=$(cat /tmp/test_procedure_order_id 2>/dev/null || echo "901")

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial counts
INITIAL_REVIEWED_COUNT=$(cat /tmp/initial_reviewed_count 2>/dev/null || echo "0")
INITIAL_NOTE_COUNT=$(cat /tmp/initial_note_count 2>/dev/null || echo "0")

echo "Task timestamps: start=$TASK_START, end=$TASK_END"
echo "Initial counts: reviewed=$INITIAL_REVIEWED_COUNT, notes=$INITIAL_NOTE_COUNT"

# Check procedure order status
echo ""
echo "=== Checking procedure order status ==="
ORDER_STATUS=$(openemr_query "SELECT order_status FROM procedure_order WHERE procedure_order_id=$PROCEDURE_ORDER_ID" 2>/dev/null)
echo "Order status: $ORDER_STATUS"

# Check procedure results status
echo ""
echo "=== Checking procedure results ==="
RESULT_STATUSES=$(openemr_query "SELECT procedure_report_id, result_status, result_text FROM procedure_result WHERE procedure_order_id=$PROCEDURE_ORDER_ID" 2>/dev/null)
echo "Result statuses:"
echo "$RESULT_STATUSES"

# Count how many results are now 'final' or 'reviewed' status
CURRENT_REVIEWED_COUNT=$(openemr_query "SELECT COUNT(*) FROM procedure_result WHERE procedure_order_id=$PROCEDURE_ORDER_ID AND result_status IN ('final', 'reviewed', 'complete')" 2>/dev/null || echo "0")
echo "Results marked as reviewed/final: $CURRENT_REVIEWED_COUNT"

# Count total results for this order
TOTAL_RESULTS=$(openemr_query "SELECT COUNT(*) FROM procedure_result WHERE procedure_order_id=$PROCEDURE_ORDER_ID" 2>/dev/null || echo "0")
echo "Total results for order: $TOTAL_RESULTS"

# Check if all results are reviewed
ALL_REVIEWED="false"
if [ "$CURRENT_REVIEWED_COUNT" -eq "$TOTAL_RESULTS" ] && [ "$TOTAL_RESULTS" -gt 0 ]; then
    ALL_REVIEWED="true"
fi
echo "All results reviewed: $ALL_REVIEWED"

# Check for new patient notes mentioning lab results
echo ""
echo "=== Checking for follow-up notes ==="
CURRENT_NOTE_COUNT=$(openemr_query "SELECT COUNT(*) FROM pnotes WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "Current notes count: $CURRENT_NOTE_COUNT (was $INITIAL_NOTE_COUNT)"

NEW_NOTE_ADDED="false"
FOLLOWUP_NOTE=""
FOLLOWUP_NOTE_DATE=""

if [ "$CURRENT_NOTE_COUNT" -gt "$INITIAL_NOTE_COUNT" ]; then
    NEW_NOTE_ADDED="true"
    # Get the most recent note for this patient
    FOLLOWUP_NOTE=$(openemr_query "SELECT body FROM pnotes WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
    FOLLOWUP_NOTE_DATE=$(openemr_query "SELECT date FROM pnotes WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
    echo "New note found: $FOLLOWUP_NOTE"
fi

# Also check for notes in other possible locations (form_vitals, form_misc_billing_options, etc.)
# Check transactions table for any follow-up documentation
TRANSACTION_NOTE=$(openemr_query "SELECT body FROM transactions WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")

# Check if note contains expected keywords
NOTE_HAS_KEYWORDS="false"
NOTE_LOWER=$(echo "$FOLLOWUP_NOTE $TRANSACTION_NOTE" | tr '[:upper:]' '[:lower:]')
if echo "$NOTE_LOWER" | grep -qE "(result|review|lipid|cholesterol|statin|continue|recheck|acceptable|normal)"; then
    NOTE_HAS_KEYWORDS="true"
    echo "Note contains expected keywords"
fi

# Check procedure_result comments for any provider notes
RESULT_COMMENTS=$(openemr_query "SELECT comments FROM procedure_result WHERE procedure_order_id=$PROCEDURE_ORDER_ID AND comments != '' AND comments IS NOT NULL ORDER BY procedure_report_id DESC LIMIT 1" 2>/dev/null || echo "")
if [ -n "$RESULT_COMMENTS" ]; then
    echo "Found result comments: $RESULT_COMMENTS"
    RESULT_COMMENTS_LOWER=$(echo "$RESULT_COMMENTS" | tr '[:upper:]' '[:lower:]')
    if echo "$RESULT_COMMENTS_LOWER" | grep -qE "(result|review|lipid|statin|continue|recheck)"; then
        NOTE_HAS_KEYWORDS="true"
    fi
fi

# Check if Firefox was running (agent interacted with the application)
FIREFOX_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    FIREFOX_RUNNING="true"
fi

# Check for any sign that lab results were accessed (via logs or state changes)
RESULTS_ACCESSED="false"
# If order status changed from pending, or results status changed, results were accessed
if [ "$ORDER_STATUS" != "pending" ] || [ "$CURRENT_REVIEWED_COUNT" -gt 0 ]; then
    RESULTS_ACCESSED="true"
fi

# Escape special characters for JSON
FOLLOWUP_NOTE_ESCAPED=$(echo "$FOLLOWUP_NOTE" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)
RESULT_COMMENTS_ESCAPED=$(echo "$RESULT_COMMENTS" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)

# Create result JSON
TEMP_JSON=$(mktemp /tmp/review_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "procedure_order_id": $PROCEDURE_ORDER_ID,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "order_status": "$ORDER_STATUS",
    "total_results": $TOTAL_RESULTS,
    "reviewed_results_count": $CURRENT_REVIEWED_COUNT,
    "all_results_reviewed": $ALL_REVIEWED,
    "results_accessed": $RESULTS_ACCESSED,
    "initial_note_count": $INITIAL_NOTE_COUNT,
    "current_note_count": $CURRENT_NOTE_COUNT,
    "new_note_added": $NEW_NOTE_ADDED,
    "followup_note": "$FOLLOWUP_NOTE_ESCAPED",
    "followup_note_date": "$FOLLOWUP_NOTE_DATE",
    "result_comments": "$RESULT_COMMENTS_ESCAPED",
    "note_has_keywords": $NOTE_HAS_KEYWORDS,
    "firefox_running": $FIREFOX_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/review_lab_results_result.json 2>/dev/null || sudo rm -f /tmp/review_lab_results_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/review_lab_results_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/review_lab_results_result.json
chmod 666 /tmp/review_lab_results_result.json 2>/dev/null || sudo chmod 666 /tmp/review_lab_results_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/review_lab_results_result.json
echo ""
echo "=== Export Complete ==="
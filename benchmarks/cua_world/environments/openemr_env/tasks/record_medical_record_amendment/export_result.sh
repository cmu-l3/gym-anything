#!/bin/bash
# Export script for Record Medical Record Amendment Task

echo "=== Exporting Medical Record Amendment Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Target patient
PATIENT_PID=3

# Get timestamps and initial counts
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_AMENDMENT_COUNT=$(cat /tmp/initial_amendment_count 2>/dev/null || echo "0")
TOTAL_INITIAL_AMENDMENTS=$(cat /tmp/total_initial_amendments 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Task timing: start=$TASK_START, end=$TASK_END"

# Get current amendment count for patient
CURRENT_AMENDMENT_COUNT=$(openemr_query "SELECT COUNT(*) FROM amendments WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
TOTAL_CURRENT_AMENDMENTS=$(openemr_query "SELECT COUNT(*) FROM amendments" 2>/dev/null || echo "0")

echo "Amendment count for patient: initial=$INITIAL_AMENDMENT_COUNT, current=$CURRENT_AMENDMENT_COUNT"
echo "Total amendments: initial=$TOTAL_INITIAL_AMENDMENTS, current=$TOTAL_CURRENT_AMENDMENTS"

# Query for all amendments for this patient (debug)
echo ""
echo "=== DEBUG: All amendments for patient PID=$PATIENT_PID ==="
openemr_query "SELECT amendment_id, pid, amendment_date, amendment_status, LEFT(amendment_desc, 100) as description FROM amendments WHERE pid=$PATIENT_PID ORDER BY amendment_id DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="

# Find the most recent amendment for this patient
NEWEST_AMENDMENT=$(openemr_query "SELECT amendment_id, pid, amendment_date, amendment_status, amendment_by, amendment_desc, created_time FROM amendments WHERE pid=$PATIENT_PID ORDER BY amendment_id DESC LIMIT 1" 2>/dev/null)

# Parse amendment data
AMENDMENT_FOUND="false"
AMENDMENT_ID=""
AMENDMENT_DATE=""
AMENDMENT_STATUS=""
AMENDMENT_BY=""
AMENDMENT_DESC=""
AMENDMENT_CREATED=""

if [ -n "$NEWEST_AMENDMENT" ] && [ "$CURRENT_AMENDMENT_COUNT" -gt "$INITIAL_AMENDMENT_COUNT" ]; then
    AMENDMENT_FOUND="true"
    
    # Parse tab-separated values
    AMENDMENT_ID=$(echo "$NEWEST_AMENDMENT" | cut -f1)
    AMENDMENT_PID=$(echo "$NEWEST_AMENDMENT" | cut -f2)
    AMENDMENT_DATE=$(echo "$NEWEST_AMENDMENT" | cut -f3)
    AMENDMENT_STATUS=$(echo "$NEWEST_AMENDMENT" | cut -f4)
    AMENDMENT_BY=$(echo "$NEWEST_AMENDMENT" | cut -f5)
    AMENDMENT_DESC=$(echo "$NEWEST_AMENDMENT" | cut -f6)
    AMENDMENT_CREATED=$(echo "$NEWEST_AMENDMENT" | cut -f7)
    
    echo ""
    echo "New amendment found:"
    echo "  ID: $AMENDMENT_ID"
    echo "  Patient PID: $AMENDMENT_PID"
    echo "  Date: $AMENDMENT_DATE"
    echo "  Status: $AMENDMENT_STATUS"
    echo "  By: $AMENDMENT_BY"
    echo "  Description: ${AMENDMENT_DESC:0:100}..."
    echo "  Created: $AMENDMENT_CREATED"
else
    echo "No new amendment found for patient"
    
    # Check if any amendment was added to wrong patient
    if [ "$TOTAL_CURRENT_AMENDMENTS" -gt "$TOTAL_INITIAL_AMENDMENTS" ]; then
        echo "WARNING: Amendment(s) may have been added to wrong patient"
        echo "Checking most recent amendment in system..."
        openemr_query "SELECT amendment_id, pid, amendment_status, LEFT(amendment_desc, 50) FROM amendments ORDER BY amendment_id DESC LIMIT 3" 2>/dev/null
    fi
fi

# Check if description contains occupation-related keywords
OCCUPATION_MENTIONED="false"
DESC_LOWER=$(echo "$AMENDMENT_DESC" | tr '[:upper:]' '[:lower:]')
if echo "$DESC_LOWER" | grep -qE "(occupation|employment|employed|job|work|nurse|lpn|licensed practical)"; then
    OCCUPATION_MENTIONED="true"
    echo "Description contains occupation-related keywords"
else
    echo "Description does NOT contain occupation-related keywords"
fi

# Check if status is approved
STATUS_APPROVED="false"
STATUS_LOWER=$(echo "$AMENDMENT_STATUS" | tr '[:upper:]' '[:lower:]')
if echo "$STATUS_LOWER" | grep -qE "(approved|accepted|accept)"; then
    STATUS_APPROVED="true"
    echo "Status indicates approval"
else
    echo "Status is NOT approved (status: $AMENDMENT_STATUS)"
fi

# Check if response field is populated (query separately)
RESPONSE_EXISTS="false"
if [ -n "$AMENDMENT_ID" ]; then
    RESPONSE_CHECK=$(openemr_query "SELECT amendment_response FROM amendments WHERE amendment_id=$AMENDMENT_ID AND amendment_response IS NOT NULL AND amendment_response != ''" 2>/dev/null)
    if [ -n "$RESPONSE_CHECK" ]; then
        RESPONSE_EXISTS="true"
        echo "Response to patient documented"
    fi
fi

# Check if created during task window
CREATED_DURING_TASK="false"
if [ -n "$AMENDMENT_CREATED" ]; then
    # Try to parse created_time to epoch
    CREATED_EPOCH=$(date -d "$AMENDMENT_CREATED" +%s 2>/dev/null || echo "0")
    if [ "$CREATED_EPOCH" -ge "$TASK_START" ] && [ "$CREATED_EPOCH" -le "$TASK_END" ]; then
        CREATED_DURING_TASK="true"
        echo "Amendment created during task window"
    else
        echo "Amendment created outside task window (created: $CREATED_EPOCH, task: $TASK_START-$TASK_END)"
    fi
fi

# Escape special characters for JSON
AMENDMENT_DESC_ESCAPED=$(echo "$AMENDMENT_DESC" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g' | tr '\n' ' ' | head -c 500)
AMENDMENT_STATUS_ESCAPED=$(echo "$AMENDMENT_STATUS" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/amendment_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_amendment_count": ${INITIAL_AMENDMENT_COUNT:-0},
    "current_amendment_count": ${CURRENT_AMENDMENT_COUNT:-0},
    "total_initial_amendments": ${TOTAL_INITIAL_AMENDMENTS:-0},
    "total_current_amendments": ${TOTAL_CURRENT_AMENDMENTS:-0},
    "new_amendment_found": $AMENDMENT_FOUND,
    "amendment": {
        "id": "$AMENDMENT_ID",
        "date": "$AMENDMENT_DATE",
        "status": "$AMENDMENT_STATUS_ESCAPED",
        "by": "$AMENDMENT_BY",
        "description": "$AMENDMENT_DESC_ESCAPED",
        "created_time": "$AMENDMENT_CREATED"
    },
    "validation": {
        "occupation_mentioned": $OCCUPATION_MENTIONED,
        "status_approved": $STATUS_APPROVED,
        "response_exists": $RESPONSE_EXISTS,
        "created_during_task": $CREATED_DURING_TASK
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result JSON
rm -f /tmp/amendment_result.json 2>/dev/null || sudo rm -f /tmp/amendment_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/amendment_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/amendment_result.json
chmod 666 /tmp/amendment_result.json 2>/dev/null || sudo chmod 666 /tmp/amendment_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/amendment_result.json"
cat /tmp/amendment_result.json

echo ""
echo "=== Export Complete ==="
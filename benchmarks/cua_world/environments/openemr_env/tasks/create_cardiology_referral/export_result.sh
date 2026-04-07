#!/bin/bash
# Export script for Create Cardiology Referral Task
# Queries database and exports results to JSON for verifier

echo "=== Exporting Create Cardiology Referral Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot saved to /tmp/task_final.png"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Target patient
PATIENT_PID=3

# Get initial counts for comparison
INITIAL_REFERRAL_COUNT=$(cat /tmp/initial_referral_count 2>/dev/null || echo "0")
INITIAL_TOTAL_TX=$(cat /tmp/initial_total_tx_count 2>/dev/null || echo "0")
EXISTING_IDS=$(cat /tmp/existing_referral_ids 2>/dev/null || echo "")

# Get current referral count for patient
CURRENT_REFERRAL_COUNT=$(openemr_query "SELECT COUNT(*) FROM transactions WHERE pid=$PATIENT_PID AND LOWER(title) LIKE '%referral%'" 2>/dev/null || echo "0")
CURRENT_TOTAL_TX=$(openemr_query "SELECT COUNT(*) FROM transactions" 2>/dev/null || echo "0")

echo "Referral count: initial=$INITIAL_REFERRAL_COUNT, current=$CURRENT_REFERRAL_COUNT"
echo "Total TX count: initial=$INITIAL_TOTAL_TX, current=$CURRENT_TOTAL_TX"

# Query for all referrals for this patient to find the newest one
echo ""
echo "=== Querying referrals for patient PID=$PATIENT_PID ==="
ALL_REFERRALS=$(openemr_query "SELECT id, date, title, pid, refer_to, refer_date, refer_diag, refer_risk_level, body, user FROM transactions WHERE pid=$PATIENT_PID AND LOWER(title) LIKE '%referral%' ORDER BY id DESC LIMIT 10" 2>/dev/null)
echo "All referrals for patient:"
echo "$ALL_REFERRALS"

# Find the newest referral (highest id that wasn't in initial list)
echo ""
echo "Looking for new referrals..."
NEWEST_REFERRAL=$(openemr_query "SELECT id, date, title, pid, refer_to, refer_date, refer_diag, refer_risk_level, body, user FROM transactions WHERE pid=$PATIENT_PID AND LOWER(title) LIKE '%referral%' ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Parse referral data
REFERRAL_FOUND="false"
REFERRAL_ID=""
REFERRAL_DATE=""
REFERRAL_TITLE=""
REFERRAL_PID=""
REFERRAL_REFER_TO=""
REFERRAL_REFER_DATE=""
REFERRAL_DIAG=""
REFERRAL_RISK=""
REFERRAL_BODY=""
REFERRAL_USER=""
IS_NEW_REFERRAL="false"

if [ -n "$NEWEST_REFERRAL" ]; then
    REFERRAL_FOUND="true"
    
    # Parse tab-separated values
    REFERRAL_ID=$(echo "$NEWEST_REFERRAL" | cut -f1)
    REFERRAL_DATE=$(echo "$NEWEST_REFERRAL" | cut -f2)
    REFERRAL_TITLE=$(echo "$NEWEST_REFERRAL" | cut -f3)
    REFERRAL_PID=$(echo "$NEWEST_REFERRAL" | cut -f4)
    REFERRAL_REFER_TO=$(echo "$NEWEST_REFERRAL" | cut -f5)
    REFERRAL_REFER_DATE=$(echo "$NEWEST_REFERRAL" | cut -f6)
    REFERRAL_DIAG=$(echo "$NEWEST_REFERRAL" | cut -f7)
    REFERRAL_RISK=$(echo "$NEWEST_REFERRAL" | cut -f8)
    REFERRAL_BODY=$(echo "$NEWEST_REFERRAL" | cut -f9)
    REFERRAL_USER=$(echo "$NEWEST_REFERRAL" | cut -f10)
    
    echo ""
    echo "Most recent referral found:"
    echo "  ID: $REFERRAL_ID"
    echo "  Date: $REFERRAL_DATE"
    echo "  Title: $REFERRAL_TITLE"
    echo "  Patient PID: $REFERRAL_PID"
    echo "  Refer To: $REFERRAL_REFER_TO"
    echo "  Refer Date: $REFERRAL_REFER_DATE"
    echo "  Diagnosis: $REFERRAL_DIAG"
    echo "  Risk Level: $REFERRAL_RISK"
    echo "  Notes: $REFERRAL_BODY"
    echo "  Created By: $REFERRAL_USER"
    
    # Check if this is a NEW referral (not in existing IDs list)
    if [ "$CURRENT_REFERRAL_COUNT" -gt "$INITIAL_REFERRAL_COUNT" ]; then
        IS_NEW_REFERRAL="true"
        echo "  Status: NEW referral (count increased)"
    elif ! echo "$EXISTING_IDS" | grep -q "^${REFERRAL_ID}$"; then
        IS_NEW_REFERRAL="true"
        echo "  Status: NEW referral (ID not in initial list)"
    else
        echo "  Status: EXISTING referral (was present before task)"
    fi
else
    echo "No referral found for patient"
fi

# Validate refer_to contains cardiology-related term
REFER_TO_VALID="false"
REFER_TO_LOWER=$(echo "$REFERRAL_REFER_TO" | tr '[:upper:]' '[:lower:]')
if echo "$REFER_TO_LOWER" | grep -qE "(cardio|heart|cardiovascular)"; then
    REFER_TO_VALID="true"
    echo "Refer To contains cardiology keyword"
else
    echo "Refer To does NOT contain cardiology keyword: '$REFERRAL_REFER_TO'"
fi

# Validate diagnosis/reason contains hypertension-related term
REASON_VALID="false"
COMBINED_REASON=$(echo "$REFERRAL_DIAG $REFERRAL_BODY" | tr '[:upper:]' '[:lower:]')
if echo "$COMBINED_REASON" | grep -qE "(hypertension|htn|blood.?pressure|bp|high.?pressure)"; then
    REASON_VALID="true"
    echo "Reason contains hypertension keyword"
else
    echo "Reason does NOT contain hypertension keyword"
fi

# Validate referral date is reasonable (today or future, not too far)
DATE_VALID="false"
if [ -n "$REFERRAL_REFER_DATE" ] && [ "$REFERRAL_REFER_DATE" != "NULL" ] && [ "$REFERRAL_REFER_DATE" != "0000-00-00" ]; then
    TODAY=$(date +%Y-%m-%d)
    # Allow dates from today to 30 days ahead
    MAX_DATE=$(date -d "+30 days" +%Y-%m-%d)
    YESTERDAY=$(date -d "-1 day" +%Y-%m-%d)
    
    # Simple string comparison works for YYYY-MM-DD format
    if [[ "$REFERRAL_REFER_DATE" >= "$YESTERDAY" ]] && [[ "$REFERRAL_REFER_DATE" <= "$MAX_DATE" ]]; then
        DATE_VALID="true"
        echo "Referral date is valid: $REFERRAL_REFER_DATE"
    else
        echo "Referral date out of range: $REFERRAL_REFER_DATE (expected $YESTERDAY to $MAX_DATE)"
    fi
else
    echo "No referral date set"
fi

# Escape special characters for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/\t/ /g' | tr '\n' ' ' | sed 's/  */ /g'
}

REFERRAL_TITLE_ESC=$(escape_json "$REFERRAL_TITLE")
REFERRAL_REFER_TO_ESC=$(escape_json "$REFERRAL_REFER_TO")
REFERRAL_DIAG_ESC=$(escape_json "$REFERRAL_DIAG")
REFERRAL_BODY_ESC=$(escape_json "$REFERRAL_BODY")
REFERRAL_RISK_ESC=$(escape_json "$REFERRAL_RISK")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/referral_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "patient_pid": $PATIENT_PID,
    "initial_referral_count": ${INITIAL_REFERRAL_COUNT:-0},
    "current_referral_count": ${CURRENT_REFERRAL_COUNT:-0},
    "initial_total_tx_count": ${INITIAL_TOTAL_TX:-0},
    "current_total_tx_count": ${CURRENT_TOTAL_TX:-0},
    "referral_found": $REFERRAL_FOUND,
    "is_new_referral": $IS_NEW_REFERRAL,
    "referral": {
        "id": "$REFERRAL_ID",
        "date": "$REFERRAL_DATE",
        "title": "$REFERRAL_TITLE_ESC",
        "pid": "$REFERRAL_PID",
        "refer_to": "$REFERRAL_REFER_TO_ESC",
        "refer_date": "$REFERRAL_REFER_DATE",
        "diagnosis": "$REFERRAL_DIAG_ESC",
        "risk_level": "$REFERRAL_RISK_ESC",
        "body": "$REFERRAL_BODY_ESC",
        "user": "$REFERRAL_USER"
    },
    "validation": {
        "refer_to_valid": $REFER_TO_VALID,
        "reason_valid": $REASON_VALID,
        "date_valid": $DATE_VALID
    },
    "screenshot_path": "/tmp/task_final.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/cardiology_referral_result.json 2>/dev/null || sudo rm -f /tmp/cardiology_referral_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/cardiology_referral_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/cardiology_referral_result.json
chmod 666 /tmp/cardiology_referral_result.json 2>/dev/null || sudo chmod 666 /tmp/cardiology_referral_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/cardiology_referral_result.json"
cat /tmp/cardiology_referral_result.json

echo ""
echo "=== Export Complete ==="
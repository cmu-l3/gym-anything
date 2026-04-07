#!/bin/bash
# Export script for Document Referral Outcome Task

echo "=== Exporting Referral Outcome Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Get target patient PID
PATIENT_PID=$(cat /tmp/target_patient_pid 2>/dev/null || echo "5")
INITIAL_REFERRAL_ID=$(cat /tmp/initial_referral_id 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_REFERRAL_COUNT=$(cat /tmp/initial_referral_count 2>/dev/null || echo "0")

echo "Patient PID: $PATIENT_PID"
echo "Initial Referral ID: $INITIAL_REFERRAL_ID"
echo "Task Start: $TASK_START"

# Get current referral count
CURRENT_REFERRAL_COUNT=$(openemr_query "SELECT COUNT(*) FROM transactions WHERE pid=$PATIENT_PID AND title LIKE '%Referral%'" 2>/dev/null || echo "0")

# Query the cardiology referral
echo ""
echo "=== Querying cardiology referral ==="
REFERRAL_DATA=$(openemr_query "SELECT id, date, title, body, pid, refer_to, refer_from, refer_date, refer_diag, refer_reply_mail, reply_date FROM transactions WHERE pid=$PATIENT_PID AND title LIKE '%Referral%' AND refer_to LIKE '%Cardiology%' ORDER BY id DESC LIMIT 1" 2>/dev/null)

echo "Raw referral data:"
echo "$REFERRAL_DATA"

# Parse referral fields
REFERRAL_FOUND="false"
REF_ID=""
REF_DATE=""
REF_TITLE=""
REF_BODY=""
REF_PID=""
REF_TO=""
REF_FROM=""
REF_REFER_DATE=""
REF_DIAG=""
REF_REPLY_MAIL=""
REF_REPLY_DATE=""

if [ -n "$REFERRAL_DATA" ]; then
    REFERRAL_FOUND="true"
    REF_ID=$(echo "$REFERRAL_DATA" | cut -f1)
    REF_DATE=$(echo "$REFERRAL_DATA" | cut -f2)
    REF_TITLE=$(echo "$REFERRAL_DATA" | cut -f3)
    REF_BODY=$(echo "$REFERRAL_DATA" | cut -f4)
    REF_PID=$(echo "$REFERRAL_DATA" | cut -f5)
    REF_TO=$(echo "$REFERRAL_DATA" | cut -f6)
    REF_FROM=$(echo "$REFERRAL_DATA" | cut -f7)
    REF_REFER_DATE=$(echo "$REFERRAL_DATA" | cut -f8)
    REF_DIAG=$(echo "$REFERRAL_DATA" | cut -f9)
    REF_REPLY_MAIL=$(echo "$REFERRAL_DATA" | cut -f10)
    REF_REPLY_DATE=$(echo "$REFERRAL_DATA" | cut -f11)
    
    echo ""
    echo "Parsed referral:"
    echo "  ID: $REF_ID"
    echo "  Date: $REF_DATE"
    echo "  Title: $REF_TITLE"
    echo "  To: $REF_TO"
    echo "  Reply Date: $REF_REPLY_DATE"
    echo "  Reply Mail: $REF_REPLY_MAIL"
    echo "  Body: $REF_BODY"
fi

# Check if referral was modified (reply_date or body changed)
INITIAL_STATE=$(cat /tmp/initial_referral_state 2>/dev/null || echo "")
STATUS_UPDATED="false"

# Check if reply_date was set (indicates completion)
if [ -n "$REF_REPLY_DATE" ] && [ "$REF_REPLY_DATE" != "NULL" ] && [ "$REF_REPLY_DATE" != "0000-00-00" ]; then
    STATUS_UPDATED="true"
    echo "Referral status appears updated (reply_date set: $REF_REPLY_DATE)"
fi

# Check if body has content (indicates notes were added)
RECOMMENDATIONS_ADDED="false"
if [ -n "$REF_BODY" ] && [ ${#REF_BODY} -gt 10 ]; then
    RECOMMENDATIONS_ADDED="true"
    echo "Recommendations appear to be documented (body has content)"
fi

# Also check refer_reply_mail field
if [ -n "$REF_REPLY_MAIL" ] && [ ${#REF_REPLY_MAIL} -gt 10 ]; then
    RECOMMENDATIONS_ADDED="true"
    echo "Recommendations found in refer_reply_mail field"
fi

# Check for expected keywords in body and reply fields
COMBINED_TEXT=$(echo "$REF_BODY $REF_REPLY_MAIL $REF_DIAG" | tr '[:upper:]' '[:lower:]')

HAS_ECHO="false"
HAS_LVH="false"
HAS_ASPIRIN="false"
HAS_BP_TARGET="false"
HAS_FOLLOWUP="false"

if echo "$COMBINED_TEXT" | grep -qE "(echocardiogram|echo)"; then
    HAS_ECHO="true"
fi
if echo "$COMBINED_TEXT" | grep -qE "(lvh|left ventricular|hypertrophy)"; then
    HAS_LVH="true"
fi
if echo "$COMBINED_TEXT" | grep -qE "(aspirin|asa)"; then
    HAS_ASPIRIN="true"
fi
if echo "$COMBINED_TEXT" | grep -qE "(130/80|130.80|target.{0,10}bp|bp.{0,10}target)"; then
    HAS_BP_TARGET="true"
fi
if echo "$COMBINED_TEXT" | grep -qE "(12 month|12.month|follow.?up|followup)"; then
    HAS_FOLLOWUP="true"
fi

echo ""
echo "Keyword checks:"
echo "  Echocardiogram mentioned: $HAS_ECHO"
echo "  LVH mentioned: $HAS_LVH"
echo "  Aspirin mentioned: $HAS_ASPIRIN"
echo "  BP target mentioned: $HAS_BP_TARGET"
echo "  Follow-up mentioned: $HAS_FOLLOWUP"

# Count keywords found
KEYWORDS_FOUND=0
[ "$HAS_ECHO" = "true" ] && KEYWORDS_FOUND=$((KEYWORDS_FOUND + 1))
[ "$HAS_LVH" = "true" ] && KEYWORDS_FOUND=$((KEYWORDS_FOUND + 1))
[ "$HAS_ASPIRIN" = "true" ] && KEYWORDS_FOUND=$((KEYWORDS_FOUND + 1))
[ "$HAS_BP_TARGET" = "true" ] && KEYWORDS_FOUND=$((KEYWORDS_FOUND + 1))
[ "$HAS_FOLLOWUP" = "true" ] && KEYWORDS_FOUND=$((KEYWORDS_FOUND + 1))

echo "Keywords found: $KEYWORDS_FOUND / 5"

# Check consultation date
CONSULTATION_DATE_MATCH="false"
if echo "$COMBINED_TEXT $REF_REPLY_DATE" | grep -qE "(2024-02-01|02.01.2024|02/01/2024|feb.{0,5}1.{0,5}2024)"; then
    CONSULTATION_DATE_MATCH="true"
fi

# Escape special characters for JSON
REF_BODY_ESCAPED=$(echo "$REF_BODY" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)
REF_REPLY_MAIL_ESCAPED=$(echo "$REF_REPLY_MAIL" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)
REF_DIAG_ESCAPED=$(echo "$REF_DIAG" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 200)

# Create result JSON
TEMP_JSON=$(mktemp /tmp/referral_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "initial_referral_id": $INITIAL_REFERRAL_ID,
    "initial_referral_count": ${INITIAL_REFERRAL_COUNT:-0},
    "current_referral_count": ${CURRENT_REFERRAL_COUNT:-0},
    "task_start_timestamp": $TASK_START,
    "referral_found": $REFERRAL_FOUND,
    "referral": {
        "id": "$REF_ID",
        "date": "$REF_DATE",
        "title": "$REF_TITLE",
        "refer_to": "$REF_TO",
        "refer_from": "$REF_FROM",
        "refer_date": "$REF_REFER_DATE",
        "refer_diag": "$REF_DIAG_ESCAPED",
        "reply_date": "$REF_REPLY_DATE",
        "reply_mail": "$REF_REPLY_MAIL_ESCAPED",
        "body": "$REF_BODY_ESCAPED"
    },
    "validation": {
        "status_updated": $STATUS_UPDATED,
        "recommendations_added": $RECOMMENDATIONS_ADDED,
        "consultation_date_match": $CONSULTATION_DATE_MATCH,
        "keywords": {
            "echocardiogram": $HAS_ECHO,
            "lvh": $HAS_LVH,
            "aspirin": $HAS_ASPIRIN,
            "bp_target": $HAS_BP_TARGET,
            "followup": $HAS_FOLLOWUP,
            "total_found": $KEYWORDS_FOUND
        }
    },
    "screenshots": {
        "initial": "/tmp/task_initial_screenshot.png",
        "final": "/tmp/task_final_screenshot.png"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/referral_outcome_result.json 2>/dev/null || sudo rm -f /tmp/referral_outcome_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/referral_outcome_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/referral_outcome_result.json
chmod 666 /tmp/referral_outcome_result.json 2>/dev/null || sudo chmod 666 /tmp/referral_outcome_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/referral_outcome_result.json"
cat /tmp/referral_outcome_result.json
echo ""
echo "=== Export Complete ==="
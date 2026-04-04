#!/bin/bash
echo "=== Exporting Token Participant Management Result ==="

source /workspace/scripts/task_utils.sh

if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$path" 2>/dev/null || DISPLAY=:1 scrot "$path" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

# Get the survey SID
SID=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid=ls.surveyls_survey_id WHERE LOWER(ls.surveyls_title) LIKE '%leadership competency%360%' LIMIT 1" 2>/dev/null || echo "")

if [ -z "$SID" ]; then
    # Try broader search
    SID=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid=ls.surveyls_survey_id WHERE LOWER(ls.surveyls_title) LIKE '%leadership%' AND LOWER(ls.surveyls_title) LIKE '%360%' LIMIT 1" 2>/dev/null || echo "")
fi
if [ -z "$SID" ]; then
    SID=$(cat /tmp/token_survey_sid 2>/dev/null || echo "")
fi

echo "Working with SID=$SID"

TOKENS_ENABLED="false"
PARTICIPANT_COUNT=0
TOKENS_GENERATED=0
INVITE_SUBJECT=""
INVITE_SUBJECT_HAS_KEYWORD="false"
PARTICIPANT_EMAILS_FOUND=""

if [ -n "$SID" ]; then
    # Check if token table exists (indicates tokens are enabled)
    TOKEN_TABLE=$(limesurvey_query "SHOW TABLES LIKE 'lime_tokens_${SID}'" 2>/dev/null || echo "")
    if [ -n "$TOKEN_TABLE" ]; then
        TOKENS_ENABLED="true"

        # Count participants
        PARTICIPANT_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_tokens_${SID}" 2>/dev/null || echo "0")
        PARTICIPANT_COUNT=${PARTICIPANT_COUNT:-0}

        # Count participants who have tokens generated (token field not empty)
        TOKENS_GENERATED=$(limesurvey_query "SELECT COUNT(*) FROM lime_tokens_${SID} WHERE token IS NOT NULL AND token != ''" 2>/dev/null || echo "0")
        TOKENS_GENERATED=${TOKENS_GENERATED:-0}

        # Get participant emails (first 10)
        PARTICIPANT_EMAILS_FOUND=$(limesurvey_query "SELECT email FROM lime_tokens_${SID} LIMIT 10" 2>/dev/null | tr '\n' ',' | sed 's/,$//')

        echo "Participant count: $PARTICIPANT_COUNT"
        echo "Tokens generated: $TOKENS_GENERATED"
        echo "Emails: $PARTICIPANT_EMAILS_FOUND"
    else
        echo "Token table lime_tokens_${SID} does NOT exist - tokens not enabled"
    fi

    # Check invitation email subject
    INVITE_SUBJECT=$(limesurvey_query "SELECT surveyls_email_invite_subj FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID AND surveyls_language='en'" 2>/dev/null || echo "")
    echo "Invite subject: $INVITE_SUBJECT"

    if echo "$INVITE_SUBJECT" | grep -qi "360.*degree\|360-degree\|360 degree\|leadership feedback"; then
        INVITE_SUBJECT_HAS_KEYWORD="true"
    fi
fi

# Check that expected emails are present
EXPECTED_EMAILS="m.thompson@acmecorp.com s.chen@acmecorp.com d.okafor@acmecorp.com p.sharma@acmecorp.com"
EMAILS_FOUND_COUNT=0
for EMAIL in $EXPECTED_EMAILS; do
    if echo "$PARTICIPANT_EMAILS_FOUND" | grep -qi "$EMAIL"; then
        EMAILS_FOUND_COUNT=$((EMAILS_FOUND_COUNT + 1))
    fi
done

# Sanitize strings for JSON
INVITE_SUBJECT_SAFE=$(echo "$INVITE_SUBJECT" | sed 's/"/\\"/g' | tr -d '\n\r' | head -c 200)
EMAILS_SAFE=$(echo "$PARTICIPANT_EMAILS_FOUND" | sed 's/"/\\"/g' | tr -d '\n\r' | head -c 300)

cat > /tmp/token_result.json << EOF
{
    "survey_id": "$SID",
    "tokens_enabled": $TOKENS_ENABLED,
    "participant_count": $PARTICIPANT_COUNT,
    "tokens_generated": $TOKENS_GENERATED,
    "invite_subject": "$INVITE_SUBJECT_SAFE",
    "invite_subject_has_keyword": $INVITE_SUBJECT_HAS_KEYWORD,
    "participant_emails_found": "$EMAILS_SAFE",
    "expected_emails_present_count": $EMAILS_FOUND_COUNT,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo ""
cat /tmp/token_result.json
echo ""
echo "=== Export Complete ==="

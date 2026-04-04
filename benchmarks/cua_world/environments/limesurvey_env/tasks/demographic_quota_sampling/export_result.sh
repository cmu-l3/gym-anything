#!/bin/bash
echo "=== Exporting Demographic Quota Sampling Result ==="

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

# Find the survey
SID=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid=ls.surveyls_survey_id WHERE LOWER(ls.surveyls_title) LIKE '%consumer electronics%' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$SID" ]; then
    SID=$(cat /tmp/quota_survey_sid 2>/dev/null || echo "")
fi

echo "Working with SID=$SID"

SURVEY_FOUND="false"
QUOTA_COUNT=0
QUOTAS_WITH_LIMIT_25=0
QUOTA_NAMES=""
QUOTA_MEMBERS_LINKED=0
GENDER_QID=""
AGE_QID=""
QUOTA_HAS_GENDER_LINK=0
QUOTA_HAS_AGE_LINK=0

if [ -n "$SID" ]; then
    SURVEY_FOUND="true"

    # Count quotas
    QUOTA_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_quota WHERE sid=$SID" 2>/dev/null || echo "0")
    QUOTA_COUNT=${QUOTA_COUNT:-0}

    # Count quotas with limit = 25
    QUOTAS_WITH_LIMIT_25=$(limesurvey_query "SELECT COUNT(*) FROM lime_quota WHERE sid=$SID AND qlimit=25" 2>/dev/null || echo "0")
    QUOTAS_WITH_LIMIT_25=${QUOTAS_WITH_LIMIT_25:-0}

    # Get quota names
    QUOTA_NAMES=$(limesurvey_query "SELECT GROUP_CONCAT(name ORDER BY id SEPARATOR '|') FROM lime_quota WHERE sid=$SID" 2>/dev/null || echo "")

    # Count quota members (answer-question links)
    QUOTA_MEMBERS_LINKED=$(limesurvey_query "SELECT COUNT(DISTINCT qm.id) FROM lime_quota_members qm JOIN lime_quota lq ON qm.quota_id=lq.id WHERE lq.sid=$SID" 2>/dev/null || echo "0")
    QUOTA_MEMBERS_LINKED=${QUOTA_MEMBERS_LINKED:-0}

    # Find GENDER and AGE_RANGE question IDs
    GENDER_QID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND title='GENDER' AND parent_qid=0 LIMIT 1" 2>/dev/null || echo "")
    AGE_QID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND title='AGE_RANGE' AND parent_qid=0 LIMIT 1" 2>/dev/null || echo "")

    # Check if quotas are linked to GENDER question
    if [ -n "$GENDER_QID" ]; then
        QUOTA_HAS_GENDER_LINK=$(limesurvey_query "SELECT COUNT(DISTINCT qm.quota_id) FROM lime_quota_members qm JOIN lime_quota lq ON qm.quota_id=lq.id WHERE lq.sid=$SID AND qm.qid=$GENDER_QID" 2>/dev/null || echo "0")
        QUOTA_HAS_GENDER_LINK=${QUOTA_HAS_GENDER_LINK:-0}
    fi

    # Check if quotas are linked to AGE_RANGE question
    if [ -n "$AGE_QID" ]; then
        QUOTA_HAS_AGE_LINK=$(limesurvey_query "SELECT COUNT(DISTINCT qm.quota_id) FROM lime_quota_members qm JOIN lime_quota lq ON qm.quota_id=lq.id WHERE lq.sid=$SID AND qm.qid=$AGE_QID" 2>/dev/null || echo "0")
        QUOTA_HAS_AGE_LINK=${QUOTA_HAS_AGE_LINK:-0}
    fi

    echo "Quota count: $QUOTA_COUNT"
    echo "Quotas with limit=25: $QUOTAS_WITH_LIMIT_25"
    echo "Quota names: $QUOTA_NAMES"
    echo "Quota members linked: $QUOTA_MEMBERS_LINKED"
    echo "Quotas linked to GENDER: $QUOTA_HAS_GENDER_LINK"
    echo "Quotas linked to AGE_RANGE: $QUOTA_HAS_AGE_LINK"
fi

QUOTA_NAMES_SAFE=$(echo "$QUOTA_NAMES" | sed 's/"/\\"/g' | tr -d '\n\r' | head -c 300)

cat > /tmp/quota_result.json << EOF
{
    "survey_id": "$SID",
    "survey_found": $SURVEY_FOUND,
    "quota_count": $QUOTA_COUNT,
    "quotas_with_limit_25": $QUOTAS_WITH_LIMIT_25,
    "quota_names": "$QUOTA_NAMES_SAFE",
    "quota_members_linked": $QUOTA_MEMBERS_LINKED,
    "quotas_linked_to_gender_question": $QUOTA_HAS_GENDER_LINK,
    "quotas_linked_to_age_question": $QUOTA_HAS_AGE_LINK,
    "gender_question_id": "$GENDER_QID",
    "age_question_id": "$AGE_QID",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo ""
cat /tmp/quota_result.json
echo ""
echo "=== Export Complete ==="

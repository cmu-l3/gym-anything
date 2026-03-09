#!/bin/bash
echo "=== Exporting Expression Manager Conditions Result ==="

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
SID=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid=ls.surveyls_survey_id WHERE LOWER(ls.surveyls_title) LIKE '%tech summit%' OR LOWER(ls.surveyls_title) LIKE '%attendee feedback%' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$SID" ]; then
    SID=$(cat /tmp/expr_survey_sid 2>/dev/null || echo "")
fi
echo "Working with SID=$SID"

SURVEY_FOUND="false"
SESSION_GROUP_HAS_CONDITION="false"
SESSION_GROUP_CONDITION=""
IMPROVE_QUESTION_HAS_CONDITION="false"
IMPROVE_QUESTION_CONDITION=""
END_URL=""
END_URL_HAS_TECHSUMMIT="false"
ATTENDED_SESSIONS_MENTIONED_IN_GROUP_COND="false"
OVERALL_RATING_MENTIONED_IN_Q_COND="false"

if [ -n "$SID" ]; then
    SURVEY_FOUND="true"

    # Find the "Session Feedback" group and check its relevance/condition
    SESSION_GID=$(limesurvey_query "SELECT gid FROM lime_groups WHERE sid=$SID AND LOWER(group_name) LIKE '%session%feedback%' LIMIT 1" 2>/dev/null || echo "")
    if [ -z "$SESSION_GID" ]; then
        # Try group_l10ns
        SESSION_GID=$(limesurvey_query "SELECT g.gid FROM lime_groups g JOIN lime_group_l10ns gl ON g.gid=gl.gid WHERE g.sid=$SID AND LOWER(gl.group_name) LIKE '%session%feedback%' LIMIT 1" 2>/dev/null || echo "")
    fi

    if [ -n "$SESSION_GID" ]; then
        SESSION_GROUP_CONDITION=$(limesurvey_query "SELECT grelevance FROM lime_groups WHERE gid=$SESSION_GID" 2>/dev/null || echo "")
        # Non-trivial condition means NOT empty, NOT just '1', NOT SQL NULL (MySQL outputs "NULL" for NULL)
        if [ -n "$SESSION_GROUP_CONDITION" ] && [ "$SESSION_GROUP_CONDITION" != "1" ] && [ "$SESSION_GROUP_CONDITION" != "" ] && [ "$SESSION_GROUP_CONDITION" != "NULL" ]; then
            SESSION_GROUP_HAS_CONDITION="true"
            # Check if it references ATTENDED_SESSIONS question
            if echo "$SESSION_GROUP_CONDITION" | grep -qi "attended_sessions\|ATTENDED\|Y\|yes"; then
                ATTENDED_SESSIONS_MENTIONED_IN_GROUP_COND="true"
            fi
        fi
    fi

    # Find IMPROVE_COMMENTS question and check its relevance
    IMPROVE_QID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND title='IMPROVE_COMMENTS' AND parent_qid=0 LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$IMPROVE_QID" ]; then
        IMPROVE_QUESTION_CONDITION=$(limesurvey_query "SELECT relevance FROM lime_questions WHERE qid=$IMPROVE_QID" 2>/dev/null || echo "")
        if [ -n "$IMPROVE_QUESTION_CONDITION" ] && [ "$IMPROVE_QUESTION_CONDITION" != "1" ] && [ "$IMPROVE_QUESTION_CONDITION" != "" ] && [ "$IMPROVE_QUESTION_CONDITION" != "NULL" ]; then
            IMPROVE_QUESTION_HAS_CONDITION="true"
            # Check if it references OVERALL_RATING and some numeric threshold
            if echo "$IMPROVE_QUESTION_CONDITION" | grep -qi "overall_rating\|OVERALL\|rating\|[<>]=\?[0-9]"; then
                OVERALL_RATING_MENTIONED_IN_Q_COND="true"
            fi
        fi
    fi

    # Check end URL
    END_URL=$(limesurvey_query "SELECT surveyls_url FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID AND surveyls_language='en'" 2>/dev/null || echo "")
    if echo "$END_URL" | grep -qi "techsummit\|tech-summit\|thank.you\|thank_you"; then
        END_URL_HAS_TECHSUMMIT="true"
    fi

    echo "Session group GID=$SESSION_GID"
    echo "Session group condition: $SESSION_GROUP_CONDITION"
    echo "Session group has condition: $SESSION_GROUP_HAS_CONDITION"
    echo "ATTENDED_SESSIONS in group condition: $ATTENDED_SESSIONS_MENTIONED_IN_GROUP_COND"
    echo "IMPROVE_COMMENTS QID=$IMPROVE_QID"
    echo "IMPROVE_COMMENTS condition: $IMPROVE_QUESTION_CONDITION"
    echo "IMPROVE_COMMENTS has condition: $IMPROVE_QUESTION_HAS_CONDITION"
    echo "OVERALL_RATING in Q condition: $OVERALL_RATING_MENTIONED_IN_Q_COND"
    echo "End URL: $END_URL"
fi

SESSION_GRP_COND_SAFE=$(echo "$SESSION_GROUP_CONDITION" | sed 's/"/\\"/g' | tr -d '\n\r' | head -c 300)
IMPROVE_COND_SAFE=$(echo "$IMPROVE_QUESTION_CONDITION" | sed 's/"/\\"/g' | tr -d '\n\r' | head -c 300)
END_URL_SAFE=$(echo "$END_URL" | sed 's/"/\\"/g' | tr -d '\n\r' | head -c 200)

cat > /tmp/expr_result.json << EOF
{
    "survey_id": "$SID",
    "survey_found": $SURVEY_FOUND,
    "session_group_has_condition": $SESSION_GROUP_HAS_CONDITION,
    "session_group_condition": "$SESSION_GRP_COND_SAFE",
    "attended_sessions_in_group_condition": $ATTENDED_SESSIONS_MENTIONED_IN_GROUP_COND,
    "improve_question_has_condition": $IMPROVE_QUESTION_HAS_CONDITION,
    "improve_question_condition": "$IMPROVE_COND_SAFE",
    "overall_rating_in_question_condition": $OVERALL_RATING_MENTIONED_IN_Q_COND,
    "end_url": "$END_URL_SAFE",
    "end_url_has_techsummit": $END_URL_HAS_TECHSUMMIT,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo ""
cat /tmp/expr_result.json
echo ""
echo "=== Export Complete ==="

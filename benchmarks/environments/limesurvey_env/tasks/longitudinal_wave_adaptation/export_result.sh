#!/bin/bash
echo "=== Exporting Longitudinal Wave Adaptation Result ==="

source /workspace/scripts/task_utils.sh

# Helper to run SQL
sql_query() {
    docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
}

# 1. Identify the New Survey ID (Wave 2)
# We look for a survey created AFTER the task started (approximately) or just by title
# Since we deleted old ones in setup, finding by title is safe.
WAVE2_SID=$(sql_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid = ls.surveyls_survey_id WHERE ls.surveyls_title LIKE '%Wave 2%' LIMIT 1")

echo "Found Wave 2 SID: $WAVE2_SID"

SURVEY_FOUND="false"
DEMOG_GROUP_EXISTS="false"
SCHOOL_GROUP_EXISTS="false"
FAMILY_GROUP_EXISTS="false"
GPA_QUESTION_EXISTS="false"
RECENT_GROUP_EXISTS="false"
MOVED_QUESTION_EXISTS="false"
MOVED_QUESTION_TYPE=""
SURVEY_ACTIVE="false"

if [ -n "$WAVE2_SID" ]; then
    SURVEY_FOUND="true"

    # Check Groups
    # Count of 'Baseline Demographics' (Should be 0)
    DEMOG_COUNT=$(sql_query "SELECT COUNT(*) FROM lime_groups WHERE sid=$WAVE2_SID AND group_name LIKE '%Baseline Demographics%'")
    if [ "$DEMOG_COUNT" -gt 0 ]; then DEMOG_GROUP_EXISTS="true"; fi

    # Count of 'School Experience' (Should be > 0)
    SCHOOL_COUNT=$(sql_query "SELECT COUNT(*) FROM lime_groups WHERE sid=$WAVE2_SID AND group_name LIKE '%School Experience%'")
    if [ "$SCHOOL_COUNT" -gt 0 ]; then SCHOOL_GROUP_EXISTS="true"; fi

    # Count of 'Family Context' (Should be > 0)
    FAMILY_COUNT=$(sql_query "SELECT COUNT(*) FROM lime_groups WHERE sid=$WAVE2_SID AND group_name LIKE '%Family Context%'")
    if [ "$FAMILY_COUNT" -gt 0 ]; then FAMILY_GROUP_EXISTS="true"; fi

    # Check for preserved question (GPA) to verify copy
    # We check by title (code) 'gpa' in the new survey
    GPA_COUNT=$(sql_query "SELECT COUNT(*) FROM lime_questions WHERE sid=$WAVE2_SID AND title='gpa'")
    if [ "$GPA_COUNT" -gt 0 ]; then GPA_QUESTION_EXISTS="true"; fi

    # Check for New Group 'Recent Changes'
    RECENT_COUNT=$(sql_query "SELECT COUNT(*) FROM lime_groups WHERE sid=$WAVE2_SID AND group_name LIKE '%Recent Changes%'")
    if [ "$RECENT_COUNT" -gt 0 ]; then RECENT_GROUP_EXISTS="true"; fi

    # Check for New Question 'moved'
    MOVED_Q_DATA=$(sql_query "SELECT type FROM lime_questions WHERE sid=$WAVE2_SID AND title='moved'")
    if [ -n "$MOVED_Q_DATA" ]; then 
        MOVED_QUESTION_EXISTS="true"
        MOVED_QUESTION_TYPE="$MOVED_Q_DATA"
    fi

    # Check Active Status
    ACTIVE_STATUS=$(sql_query "SELECT active FROM lime_surveys WHERE sid=$WAVE2_SID")
    if [ "$ACTIVE_STATUS" == "Y" ]; then SURVEY_ACTIVE="true"; fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON Output
cat > /tmp/task_result.json <<EOF
{
    "survey_found": $SURVEY_FOUND,
    "sid": "$WAVE2_SID",
    "demog_group_exists": $DEMOG_GROUP_EXISTS,
    "school_group_exists": $SCHOOL_GROUP_EXISTS,
    "family_group_exists": $FAMILY_GROUP_EXISTS,
    "gpa_question_exists": $GPA_QUESTION_EXISTS,
    "recent_group_exists": $RECENT_GROUP_EXISTS,
    "moved_question_exists": $MOVED_QUESTION_EXISTS,
    "moved_question_type": "$MOVED_QUESTION_TYPE",
    "survey_active": $SURVEY_ACTIVE,
    "timestamp": "$(date +%s)"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
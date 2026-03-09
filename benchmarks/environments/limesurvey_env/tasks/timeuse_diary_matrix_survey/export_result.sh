#!/bin/bash
echo "=== Exporting Time-Use Diary Survey Results ==="

source /workspace/scripts/task_utils.sh

# Function to run SQL safely
db_query() {
    docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
}

# Capture final state
take_screenshot /tmp/task_final.png

# 1. Find the created survey
# We look for surveys created AFTER the task start time, matching the title keywords
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task start time: $TASK_START"

# Find SID based on title
SID=$(db_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid = ls.surveyls_survey_id WHERE LOWER(ls.surveyls_title) LIKE '%time%allocation%' OR LOWER(ls.surveyls_title) LIKE '%student%life%' ORDER BY s.datecreated DESC LIMIT 1")

echo "Found SID: $SID"

# Initialize variables
SURVEY_FOUND="false"
TITLE=""
FORMAT=""
ACTIVE=""
GROUP_COUNT=0
QUESTION_FOUND="false"
Q_TYPE=""
Y_AXIS_COUNT=0
X_AXIS_COUNT=0
MIN_VAL=""
MAX_VAL=""

if [ -n "$SID" ]; then
    SURVEY_FOUND="true"
    
    # Get Title
    TITLE=$(db_query "SELECT surveyls_title FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID LIMIT 1")
    
    # Get Format (G=Group by Group, A=All in one, etc)
    FORMAT=$(db_query "SELECT format FROM lime_surveys WHERE sid=$SID")
    
    # Get Active Status
    ACTIVE=$(db_query "SELECT active FROM lime_surveys WHERE sid=$SID")
    
    # Count Groups
    GROUP_COUNT=$(db_query "SELECT COUNT(*) FROM lime_groups WHERE sid=$SID")
    
    # Find Array (Numbers) Question (Type ':')
    # We look for the question specifically in this survey
    QID=$(db_query "SELECT qid FROM lime_questions WHERE sid=$SID AND type=':' AND parent_qid=0 LIMIT 1")
    
    if [ -n "$QID" ]; then
        QUESTION_FOUND="true"
        Q_TYPE=":"
        
        # Count Y-axis subquestions (scale_id = 0)
        Y_AXIS_COUNT=$(db_query "SELECT COUNT(*) FROM lime_questions WHERE parent_qid=$QID AND scale_id=0")
        
        # Count X-axis subquestions (scale_id = 1)
        X_AXIS_COUNT=$(db_query "SELECT COUNT(*) FROM lime_questions WHERE parent_qid=$QID AND scale_id=1")
        
        # Check Attributes for Min/Max
        # Note: Attribute names can vary slightly by version, but usually 'multiflexible_min'/'max' for this type
        MIN_VAL=$(db_query "SELECT value FROM lime_question_attributes WHERE qid=$QID AND attribute='multiflexible_min'")
        MAX_VAL=$(db_query "SELECT value FROM lime_question_attributes WHERE qid=$QID AND attribute='multiflexible_max'")
        
        # Fallback check for older attribute names if needed
        if [ -z "$MIN_VAL" ]; then
            MIN_VAL=$(db_query "SELECT value FROM lime_question_attributes WHERE qid=$QID AND attribute='min_num_value_n'")
        fi
        if [ -z "$MAX_VAL" ]; then
            MAX_VAL=$(db_query "SELECT value FROM lime_question_attributes WHERE qid=$QID AND attribute='max_num_value_n'")
        fi
    fi
fi

# Create JSON
cat > /tmp/export_data.json << EOF
{
    "survey_found": $SURVEY_FOUND,
    "sid": "$SID",
    "title": "$(echo $TITLE | sed 's/"/\\"/g')",
    "format": "$FORMAT",
    "active": "$ACTIVE",
    "group_count": $GROUP_COUNT,
    "question_found": $QUESTION_FOUND,
    "question_type": "$Q_TYPE",
    "y_axis_count": $Y_AXIS_COUNT,
    "x_axis_count": $X_AXIS_COUNT,
    "min_val": "$MIN_VAL",
    "max_val": "$MAX_VAL",
    "timestamp": $(date +%s)
}
EOF

# Move to safe location
export_json_result "$(cat /tmp/export_data.json)" "/tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="
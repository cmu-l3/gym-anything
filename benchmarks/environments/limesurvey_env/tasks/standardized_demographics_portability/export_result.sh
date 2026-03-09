#!/bin/bash
echo "=== Exporting Demographics Portability Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check File Artifact
EXPORT_FILE="/home/ga/Documents/standard_demographics.lsg"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$EXPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$EXPORT_FILE")
    FILE_MTIME=$(stat -c %Y "$EXPORT_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Database Verification Helper
# Find Survey IDs by title
SOURCE_SID=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title = 'Lab Master Template' ORDER BY surveyls_survey_id DESC LIMIT 1")
TARGET_SID=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title = 'Social Interaction Study 2024' ORDER BY surveyls_survey_id DESC LIMIT 1")

# Function to get group and question info
check_survey_content() {
    local sid="$1"
    if [ -z "$sid" ]; then
        echo "{}"
        return
    fi
    
    # Check for group "Standard Demographics"
    local has_group=$(limesurvey_query "SELECT count(*) FROM lime_groups WHERE sid=$sid AND group_name='Standard Demographics'")
    
    # Check for specific questions
    local q_age=$(limesurvey_query "SELECT count(*) FROM lime_questions WHERE sid=$sid AND title='DEMO_AGE' AND type='N'")
    local q_edu=$(limesurvey_query "SELECT count(*) FROM lime_questions WHERE sid=$sid AND title='DEMO_EDU' AND type='L'")
    local q_emp=$(limesurvey_query "SELECT count(*) FROM lime_questions WHERE sid=$sid AND title='DEMO_EMP' AND type='Y'")
    
    # Check answer options for DEMO_EDU (need to find the QID first)
    local edu_qid=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$sid AND title='DEMO_EDU' LIMIT 1")
    local edu_options_count=0
    if [ -n "$edu_qid" ]; then
        edu_options_count=$(limesurvey_query "SELECT count(*) FROM lime_answers WHERE qid=$edu_qid")
    fi
    
    # Construct JSON snippet
    echo "{\"sid\": \"$sid\", \"has_group\": $has_group, \"q_age\": $q_age, \"q_edu\": $q_edu, \"q_emp\": $q_emp, \"edu_options\": $edu_options_count}"
}

echo "Checking Source Survey..."
SOURCE_DATA=$(check_survey_content "$SOURCE_SID")

echo "Checking Target Survey..."
TARGET_DATA=$(check_survey_content "$TARGET_SID")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_check": {
        "exists": $FILE_EXISTS,
        "created_during_task": $FILE_CREATED_DURING_TASK,
        "size": $FILE_SIZE,
        "path": "$EXPORT_FILE"
    },
    "source_survey": $SOURCE_DATA,
    "target_survey": $TARGET_DATA
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Define DB Query helper
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Get the survey ID for the target survey
SURVEY_ID=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title = 'IT Incident Report Form 2025' LIMIT 1")

if [ -z "$SURVEY_ID" ]; then
    echo "Error: Survey not found!"
    SURVEY_FOUND="false"
    ADMIN_EMAIL_SETTING=""
else
    SURVEY_FOUND="true"
    # Query the 'email_admin_responses' column which holds the Detailed Admin Notification setting
    # We use sed to escape double quotes for JSON safety
    ADMIN_EMAIL_SETTING=$(limesurvey_query "SELECT email_admin_responses FROM lime_surveys WHERE sid = $SURVEY_ID")
fi

echo "Found setting: $ADMIN_EMAIL_SETTING"

# Sanitize setting for JSON (escape quotes and backslashes)
SAFE_SETTING=$(echo "$ADMIN_EMAIL_SETTING" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')

# Create JSON result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "survey_found": $SURVEY_FOUND,
    "survey_id": "$SURVEY_ID",
    "admin_email_setting": "$SAFE_SETTING",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="
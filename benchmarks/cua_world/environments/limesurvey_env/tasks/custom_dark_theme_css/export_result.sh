#!/bin/bash
echo "=== Exporting Custom Dark Theme Results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- VERIFICATION DATA COLLECTION ---

# 1. Check Survey Existence and Assigned Template
SURVEY_TITLE="Night Shift Worker Experience"
SURVEY_DATA=$(limesurvey_query "SELECT s.sid, s.template, sl.surveyls_title 
FROM lime_surveys s 
JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id 
WHERE sl.surveyls_title LIKE '%Night Shift Worker Experience%' 
LIMIT 1")

SURVEY_FOUND="false"
SURVEY_SID=""
ASSIGNED_TEMPLATE=""
ACTUAL_TITLE=""

if [ -n "$SURVEY_DATA" ]; then
    SURVEY_FOUND="true"
    SURVEY_SID=$(echo "$SURVEY_DATA" | awk '{print $1}')
    ASSIGNED_TEMPLATE=$(echo "$SURVEY_DATA" | awk '{print $2}')
    # Capture title (handling spaces roughly)
    ACTUAL_TITLE=$(echo "$SURVEY_DATA" | cut -d' ' -f3-) 
fi

# 2. Check Theme Directory Existence
THEME_NAME="NightShiftDark"
THEME_DIR="/var/www/html/upload/themes/survey/$THEME_NAME"
THEME_EXISTS="false"
CSS_FILE_EXISTS="false"
CSS_CONTENT=""

if [ -d "$THEME_DIR" ]; then
    THEME_EXISTS="true"
    # Check for custom.css
    CSS_PATH="$THEME_DIR/css/custom.css"
    if [ -f "$CSS_PATH" ]; then
        CSS_FILE_EXISTS="true"
        # Read content, escape for JSON
        CSS_CONTENT=$(cat "$CSS_PATH" | tr '\n' ' ' | sed 's/"/\\"/g')
    fi
fi

# 3. Create JSON Result
JSON_OUTPUT="/tmp/task_result.json"

cat > "$JSON_OUTPUT" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "survey_found": $SURVEY_FOUND,
    "survey_sid": "$SURVEY_SID",
    "assigned_template": "$ASSIGNED_TEMPLATE",
    "actual_title": "$ACTUAL_TITLE",
    "theme_exists": $THEME_EXISTS,
    "theme_path": "$THEME_DIR",
    "css_file_exists": $CSS_FILE_EXISTS,
    "css_content": "$CSS_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 "$JSON_OUTPUT"

echo "Export complete. Data saved to $JSON_OUTPUT"
cat "$JSON_OUTPUT"
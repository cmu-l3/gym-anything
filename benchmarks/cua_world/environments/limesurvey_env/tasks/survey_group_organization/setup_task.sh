#!/bin/bash
echo "=== Setting up Survey Group Organization Task ==="

source /workspace/scripts/task_utils.sh

# Fallback for query helper if not sourced correctly
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# 1. Clean up any previous attempts (Anti-gaming/Clean state)
echo "Cleaning up previous task artifacts..."
# Delete surveys with matching titles
IDS=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%Tech Summit%' OR surveyls_title LIKE '%Healthcare Innovation%' OR surveyls_title LIKE '%Women in Leadership%'")
for id in $IDS; do
    if [ -n "$id" ]; then
        echo "Deleting survey $id..."
        limesurvey_query "DELETE FROM lime_surveys WHERE sid=$id"
        limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$id"
        limesurvey_query "DELETE FROM lime_questions WHERE sid=$id"
        limesurvey_query "DELETE FROM lime_groups WHERE sid=$id"
    fi
done

# Delete groups with matching titles
limesurvey_query "DELETE FROM lime_surveys_groups WHERE title LIKE '%Tech Summit%'"
limesurvey_query "DELETE FROM lime_surveys_groups WHERE title LIKE '%Healthcare Innovation%'"
limesurvey_query "DELETE FROM lime_surveys_groups WHERE title LIKE '%Women in Leadership%'"

# 2. Record initial state
INITIAL_GROUP_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_surveys_groups" 2>/dev/null || echo "0")
echo "$INITIAL_GROUP_COUNT" > /tmp/initial_group_count
echo "Initial survey group count: $INITIAL_GROUP_COUNT"

# Record start time
date +%s > /tmp/task_start_time.txt

# 3. Ensure Firefox is open to Admin
echo "Ensuring Firefox is running..."
focus_firefox
# Navigate to survey groups page to give a hint/start location, or just dashboard
DISPLAY=:1 xdotool type "http://localhost/index.php/admin/survey/sa/listquestiongroups" 2>/dev/null
# Actually, let's just go to main admin
DISPLAY=:1 xdotool key ctrl+l 2>/dev/null
sleep 0.5
DISPLAY=:1 xdotool type "http://localhost/index.php/admin" 2>/dev/null
DISPLAY=:1 xdotool key Return 2>/dev/null
sleep 3

# Take screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
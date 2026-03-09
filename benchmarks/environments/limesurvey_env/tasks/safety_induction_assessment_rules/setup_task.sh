#!/bin/bash
echo "=== Setting up Safety Induction Assessment Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for LimeSurvey to be fully ready
wait_for_page_load 5

# Clean up any previous surveys with conflicting titles to ensure fresh start
echo "Cleaning up previous surveys..."
limesurvey_query "SELECT sid FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%Safety Induction%'" | while read SID; do
    if [ -n "$SID" ]; then
        echo "Deleting old survey SID: $SID"
        limesurvey_query "DELETE FROM lime_surveys WHERE sid=$SID"
        limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID"
        limesurvey_query "DELETE FROM lime_questions WHERE sid=$SID"
        limesurvey_query "DELETE FROM lime_groups WHERE sid=$SID"
        limesurvey_query "DELETE FROM lime_assessments WHERE sid=$SID"
        limesurvey_query "DROP TABLE IF EXISTS lime_survey_$SID"
    fi
done

# Record initial survey count
INITIAL_COUNT=$(get_survey_count)
echo "$INITIAL_COUNT" > /tmp/initial_survey_count

# Ensure Firefox is running and focused
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 5
fi

# Maximize and focus
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
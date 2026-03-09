#!/bin/bash
echo "=== Setting up Array Filter Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for LimeSurvey to be ready
wait_for_page_load 5

# Clean up any existing surveys that might match the target to ensure a fresh start
echo "Cleaning up previous attempts..."
limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings sl ON s.sid=sl.surveyls_survey_id WHERE sl.surveyls_title LIKE '%Streaming%'" | while read sid; do
    if [ -n "$sid" ]; then
        echo "Deleting existing survey SID: $sid"
        # We delete from lime_surveys; cascade should handle the rest in a real DB, 
        # but for safety in this environment we just drop the main entry or use API if available.
        # Simple DB deletion is often enough for the verifier to not see it.
        limesurvey_query "DELETE FROM lime_surveys WHERE sid=$sid"
        limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$sid"
        limesurvey_query "DELETE FROM lime_questions WHERE sid=$sid"
        limesurvey_query "DELETE FROM lime_groups WHERE sid=$sid"
    fi
done

# Ensure Firefox is running and focused
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 5
else
    focus_firefox
    DISPLAY=:1 xdotool key ctrl+l
    DISPLAY=:1 xdotool type "http://localhost/index.php/admin"
    DISPLAY=:1 xdotool key Return
    sleep 3
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
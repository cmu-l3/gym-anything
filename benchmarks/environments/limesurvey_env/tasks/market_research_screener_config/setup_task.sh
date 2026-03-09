#!/bin/bash
echo "=== Setting up Market Research Screener Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for LimeSurvey to be ready
for i in {1..30}; do
    if curl -s http://localhost/index.php/admin > /dev/null; then
        echo "LimeSurvey is ready."
        break
    fi
    sleep 2
done

# Clean up any existing surveys that might match the target title to ensure a fresh start
echo "Cleaning up old surveys..."
limesurvey_query "DELETE FROM lime_surveys WHERE sid IN (SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%Streaming%')" 2>/dev/null || true
limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%Streaming%'" 2>/dev/null || true

# Focus Firefox on the admin page
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 5
fi

# Ensure window is maximized and focused
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
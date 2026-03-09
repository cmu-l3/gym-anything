#!/bin/bash
echo "=== Setting up Multilingual Trust Survey Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for LimeSurvey to be responsive
wait_for_page_load 5

# Remove any existing surveys with conflicting titles to ensure clean state
# We use a python script to interact with the API or DB directly if possible, 
# but direct DB is safer for setup scripts in this environment.
echo "Cleaning up old surveys..."
limesurvey_query "DELETE FROM lime_surveys WHERE sid IN (SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%Social Trust%' OR surveyls_title LIKE '%Confianza Social%')" 2>/dev/null || true
limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%Social Trust%' OR surveyls_title LIKE '%Confianza Social%'" 2>/dev/null || true

# Record initial counts
INITIAL_SURVEY_COUNT=$(get_survey_count)
echo "$INITIAL_SURVEY_COUNT" > /tmp/initial_survey_count.txt

# Ensure Firefox is running and focused on LimeSurvey admin
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 10
else
    # Reload page to ensure clean state
    focus_firefox
    DISPLAY=:1 xdotool key F5
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
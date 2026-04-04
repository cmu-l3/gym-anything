#!/bin/bash
set -e
echo "=== Setting up Standardized Demographics Portability Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create Documents directory if it doesn't exist
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up any previous run artifacts
rm -f /home/ga/Documents/standard_demographics.lsg
rm -f /tmp/demographics_result.json

# Define DB query helper if not present
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Clean up existing surveys with the target names to ensure a fresh start
echo "Cleaning up old surveys..."
# We use a python script to interact with the DB/API for safe deletion or just direct DB
limesurvey_query "DELETE FROM lime_surveys WHERE sid IN (SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title IN ('Lab Master Template', 'Social Interaction Study 2024'))"
limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_title IN ('Lab Master Template', 'Social Interaction Study 2024')"
# Note: Cascading deletes might not happen purely via SQL in LimeSurvey, but for the purpose of the task,
# hiding them from the list is usually sufficient. A more robust way is via API if available, 
# but direct SQL cleanup of the main tables usually breaks the link so they don't appear in the UI.

# Ensure Firefox is ready
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 5
fi

# Wait for window and maximize
wait_for_window "Firefox" 30
focus_firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record initial state
INITIAL_SURVEY_COUNT=$(get_survey_count)
echo "$INITIAL_SURVEY_COUNT" > /tmp/initial_survey_count

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
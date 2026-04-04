#!/bin/bash
echo "=== Setting up CRM Integration Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# Helper for DB queries
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Helper for screenshots
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$path" 2>/dev/null || DISPLAY=:1 scrot "$path" 2>/dev/null || true
    }
fi

# Wait for LimeSurvey
echo "Waiting for LimeSurvey..."
for i in {1..30}; do
    if curl -s http://localhost/index.php/admin >/dev/null; then
        echo "LimeSurvey is ready."
        break
    fi
    sleep 2
done

# Cleanup: Remove any existing surveys with "Zendesk" in the title to ensure clean state
echo "Cleaning up existing surveys..."
EXISTS=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%Zendesk%'")
if [ -n "$EXISTS" ]; then
    for sid in $EXISTS; do
        echo "Deleting old survey SID: $sid"
        limesurvey_query "DELETE FROM lime_surveys WHERE sid=$sid"
        limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$sid"
        limesurvey_query "DELETE FROM lime_questions WHERE sid=$sid"
        limesurvey_query "DELETE FROM lime_groups WHERE sid=$sid"
        limesurvey_query "DELETE FROM lime_survey_url_parameters WHERE sid=$sid"
    done
fi

# Record initial counts
INITIAL_SURVEYS=$(limesurvey_query "SELECT COUNT(*) FROM lime_surveys")
echo "$INITIAL_SURVEYS" > /tmp/initial_survey_count

# Setup Firefox
echo "Launching Firefox..."
focus_firefox
DISPLAY=:1 xdotool type "http://localhost/index.php/admin"
DISPLAY=:1 xdotool key Return
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
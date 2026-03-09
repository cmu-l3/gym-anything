#!/bin/bash
echo "=== Setting up Community Needs Survey Config Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definition for limesurvey_query if task_utils doesn't have it
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Wait for LimeSurvey to be ready
for i in $(seq 1 30); do
    if curl -s "http://localhost/index.php/admin" > /dev/null; then
        echo "LimeSurvey is reachable."
        break
    fi
    echo "Waiting for LimeSurvey... ($i)"
    sleep 2
done

# Cleanup: Delete any existing surveys with conflicting titles to ensure a clean state
# This prevents the verifier from finding an old correct survey and passing the agent
echo "Cleaning up existing surveys..."
SURVEYS_TO_DELETE=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE LOWER(surveyls_title) LIKE '%riverside%' OR LOWER(surveyls_title) LIKE '%community needs%'")

if [ -n "$SURVEYS_TO_DELETE" ]; then
    for SID in $SURVEYS_TO_DELETE; do
        echo "Deleting existing survey SID: $SID"
        # We delete from the main table, cascading should handle the rest or we do minimal cleanup
        limesurvey_query "DELETE FROM lime_surveys WHERE sid=$SID"
        limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID"
        limesurvey_query "DELETE FROM lime_groups WHERE sid=$SID"
        limesurvey_query "DELETE FROM lime_questions WHERE sid=$SID"
    done
fi

# Record start time for anti-gaming (to ensure survey is created AFTER this timestamp)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Record initial survey count
INITIAL_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_surveys" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_survey_count

# Ensure Firefox is open to the admin page
echo "Ensuring Firefox is open..."
focus_firefox
if ! pgrep -f "firefox" > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 5
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="
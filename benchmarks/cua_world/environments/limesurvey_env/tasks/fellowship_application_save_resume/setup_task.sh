#!/bin/bash
echo "=== Setting up Fellowship Application Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if utils not loaded
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$path" 2>/dev/null || DISPLAY=:1 scrot "$path" 2>/dev/null || true
    }
fi

# Wait for LimeSurvey readiness
echo "Waiting for LimeSurvey..."
for i in {1..30}; do
    if curl -s http://localhost/index.php/admin >/dev/null; then
        echo "LimeSurvey is ready."
        break
    fi
    sleep 2
done

# Clean up any previous attempts (surveys with similar titles)
echo "Cleaning up previous surveys..."
IDS_TO_DELETE=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings sl ON s.sid=sl.surveyls_survey_id WHERE sl.surveyls_title LIKE '%Doctoral Research Fellowship%'")
for SID in $IDS_TO_DELETE; do
    if [ -n "$SID" ]; then
        echo "Deleting survey SID: $SID"
        limesurvey_query "DELETE FROM lime_surveys WHERE sid=$SID"
        limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID"
        limesurvey_query "DELETE FROM lime_questions WHERE sid=$SID"
        limesurvey_query "DELETE FROM lime_groups WHERE sid=$SID"
        limesurvey_query "DROP TABLE IF EXISTS lime_survey_$SID"
    fi
done

# Record start time
date +%s > /tmp/task_start_time.txt

# Record initial survey count
INITIAL_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_surveys")
echo "$INITIAL_COUNT" > /tmp/initial_survey_count.txt

# Open Firefox to Admin Login
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 10
else
    # If running, focus and navigate
    focus_firefox
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost/index.php/admin"
    DISPLAY=:1 xdotool key Return
    sleep 3
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
#!/bin/bash
set -e
echo "=== Setting up NPS Equation Classification Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definition for limesurvey_query if not present in environment
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for LimeSurvey to be ready
echo "Checking LimeSurvey availability..."
for i in {1..30}; do
    if curl -s http://localhost/index.php/admin > /dev/null; then
        echo "LimeSurvey is ready."
        break
    fi
    sleep 2
done

# Clean up any existing surveys that might match the task to ensure a fresh start
# This prevents the agent from editing an old survey instead of creating one
echo "Cleaning up existing NPS surveys..."
IDS_TO_DELETE=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id WHERE LOWER(sl.surveyls_title) LIKE '%nps%' OR LOWER(sl.surveyls_title) LIKE '%net promoter%'")

if [ -n "$IDS_TO_DELETE" ]; then
    for SID in $IDS_TO_DELETE; do
        echo "Removing stale survey SID: $SID"
        limesurvey_query "DELETE FROM lime_surveys WHERE sid=$SID"
        limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID"
        limesurvey_query "DELETE FROM lime_questions WHERE sid=$SID"
        limesurvey_query "DELETE FROM lime_groups WHERE sid=$SID"
        limesurvey_query "DROP TABLE IF EXISTS lime_survey_$SID"
    done
fi

# Record initial survey count
INITIAL_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_surveys")
echo "$INITIAL_COUNT" > /tmp/initial_survey_count

# Launch Firefox
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
fi

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox" > /dev/null; then
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
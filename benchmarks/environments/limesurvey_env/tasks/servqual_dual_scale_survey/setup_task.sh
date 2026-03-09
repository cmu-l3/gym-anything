#!/bin/bash
echo "=== Setting up SERVQUAL Dual Scale Survey Task ==="

source /workspace/scripts/task_utils.sh

# Fallback for database query function if not loaded
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# 1. Wait for LimeSurvey to be fully ready
echo "Checking LimeSurvey availability..."
for i in {1..30}; do
    if curl -s http://localhost/index.php/admin > /dev/null; then
        echo "LimeSurvey is reachable."
        break
    fi
    sleep 2
done

# 2. Clean up any existing surveys that might conflict (to ensure fresh start)
echo "Cleaning up potential conflicting surveys..."
EXISTING_IDS=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE LOWER(surveyls_title) LIKE '%servqual%' OR LOWER(surveyls_title) LIKE '%service quality%'")
for sid in $EXISTING_IDS; do
    if [ -n "$sid" ]; then
        echo "Deleting existing survey SID: $sid"
        # We delete from lime_surveys; cascading deletes should handle the rest in a real DB, 
        # but for LimeSurvey logical deletion is safer via API. 
        # Since we don't have easy API access in shell, we'll try DB delete which might leave orphans but clears the UI list.
        limesurvey_query "DELETE FROM lime_surveys WHERE sid=$sid"
        limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$sid"
    fi
done

# 3. Record initial state
INITIAL_SURVEY_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_surveys" 2>/dev/null || echo "0")
echo "$INITIAL_SURVEY_COUNT" > /tmp/initial_survey_count
date +%s > /tmp/task_start_time

# 4. Launch Firefox
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 5
fi

# 5. Focus and Maximize
echo "Focusing window..."
for i in {1..10}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox\|limesurvey"; then
        DISPLAY=:1 wmctrl -a "Firefox"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
        break
    fi
    sleep 1
done

# 6. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
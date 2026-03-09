#!/bin/bash
echo "=== Setting up Employee Exit Interview Task ==="

source /workspace/scripts/task_utils.sh

# Fallback query function if utils not loaded correctly
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# 1. Wait for LimeSurvey to be ready
echo "Checking LimeSurvey availability..."
for i in $(seq 1 30); do
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/index.php/admin 2>/dev/null || echo "000")
    if [ "$HTTP" = "200" ] || [ "$HTTP" = "302" ]; then
        echo "LimeSurvey ready (HTTP $HTTP)"
        break
    fi
    sleep 2
done

# 2. Clean up any existing surveys with the target name to ensure a fresh start
echo "Cleaning up old surveys..."
# Get IDs of surveys with "Exit Interview" in title
OLD_IDS=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings sl ON s.sid=sl.surveyls_survey_id WHERE sl.surveyls_title LIKE '%Exit Interview%'")

for sid in $OLD_IDS; do
    if [ -n "$sid" ]; then
        echo "Removing previous survey SID: $sid"
        # We need to drop tables carefully or just delete from main table and let cascade handle it (if configured)
        # Using a safer approach: just delete metadata, which hides it from UI. 
        # For a full cleanup we'd use the API, but DB deletion is faster for setup.
        limesurvey_query "DELETE FROM lime_surveys WHERE sid=$sid"
        limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$sid"
        limesurvey_query "DELETE FROM lime_questions WHERE sid=$sid"
        limesurvey_query "DELETE FROM lime_groups WHERE sid=$sid"
        limesurvey_query "DROP TABLE IF EXISTS lime_survey_$sid"
    fi
done

# 3. Record start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Open Firefox to Admin Login
echo "Launching Firefox..."
focus_firefox
DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers "http://localhost/index.php/admin" 2>/dev/null || true
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
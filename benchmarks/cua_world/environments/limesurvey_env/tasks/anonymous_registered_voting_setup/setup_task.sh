#!/bin/bash
echo "=== Setting up Anonymous Registered Voting Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Function to execute SQL in LimeSurvey DB
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Cleanup: Remove any existing surveys with similar titles to avoid confusion
echo "Cleaning up old surveys..."
IDS_TO_DELETE=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid=ls.surveyls_survey_id WHERE LOWER(ls.surveyls_title) LIKE '%employee benefits%' OR LOWER(ls.surveyls_title) LIKE '%vote%'")
for SID in $IDS_TO_DELETE; do
    if [ -n "$SID" ]; then
        echo "Deleting old survey $SID..."
        # Drop token table if exists
        limesurvey_query "DROP TABLE IF EXISTS lime_tokens_$SID" 2>/dev/null
        # Drop survey tables (cascading delete usually handled by app, but manual cleanup safe here)
        limesurvey_query "DELETE FROM lime_surveys WHERE sid=$SID" 2>/dev/null
        limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID" 2>/dev/null
    fi
done

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

# Ensure Firefox is running and focused on LimeSurvey admin
echo "Launching/Focusing Firefox..."
focus_firefox
# Navigate to admin login
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool type "http://localhost/index.php/admin"
DISPLAY=:1 xdotool key Return
sleep 3

echo "=== Setup Complete ==="
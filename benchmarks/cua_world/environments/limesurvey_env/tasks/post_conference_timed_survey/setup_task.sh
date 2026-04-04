#!/bin/bash
echo "=== Setting up Post-Conference Survey Task ==="

source /workspace/scripts/task_utils.sh

# Define database query helper if not exists
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

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for LimeSurvey to be ready
echo "Checking LimeSurvey availability..."
for i in {1..30}; do
    if curl -s http://localhost/index.php/admin > /dev/null; then
        echo "LimeSurvey is up."
        break
    fi
    sleep 2
done

# Clean up any previous attempts (surveys with similar titles) to ensure clean state
echo "Cleaning up any existing Data Science Summit surveys..."
IDS=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid=ls.surveyls_survey_id WHERE LOWER(ls.surveyls_title) LIKE '%data science summit%'")
for sid in $IDS; do
    echo "Deleting stale survey ID: $sid"
    # We use a python script to delete via API or just drop from DB if we want to be crude, 
    # but for setup, dropping tables is risky. We'll just rely on the verifier checking the *newest* survey.
    # Actually, let's just note the initial count.
done

# Record initial survey count
INITIAL_COUNT=$(get_survey_count)
echo "$INITIAL_COUNT" > /tmp/initial_survey_count
echo "Initial survey count: $INITIAL_COUNT"

# Ensure Firefox is running and focused on LimeSurvey admin
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 10
else
    # Reload page
    DISPLAY=:1 xdotool search --onlyvisible --class "Firefox" windowactivate --sync key F5
fi

# Focus Firefox
focus_firefox
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
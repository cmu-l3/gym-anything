#!/bin/bash
set -e
echo "=== Setting up Kiosk Lead Capture Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial survey count to detect creation
INITIAL_COUNT=$(get_survey_count)
echo "$INITIAL_COUNT" > /tmp/initial_survey_count

# Ensure Firefox is running and focused on LimeSurvey admin
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 5
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i -E "(firefox|limesurvey|mozilla)"; then
        echo "Firefox detected."
        break
    fi
    sleep 1
done

# Focus and maximize
focus_firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Check if a survey with the target name already exists (to avoid ambiguity)
# If it exists, we rename it to "Backup" so the agent has a clean slate
EXISTING_SID=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title = 'TechInnovate 2026 Lead Capture' LIMIT 1")
if [ -n "$EXISTING_SID" ]; then
    echo "Renaming existing conflicting survey (SID: $EXISTING_SID)..."
    limesurvey_query "UPDATE lime_surveys_languagesettings SET surveyls_title = 'TechInnovate 2026 Lead Capture (Backup)' WHERE surveyls_survey_id = $EXISTING_SID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
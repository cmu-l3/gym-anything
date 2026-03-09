#!/bin/bash
echo "=== Setting up SaaS Pricing Matrix Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure LimeSurvey is ready
echo "Checking LimeSurvey status..."
wait_for_page_load 5

# Clean up any previous attempts (Adversarial/Reset)
# We delete any survey with "SaaS" or "Pricing" in the title to ensure a clean state
# This forces the agent to actually create it, not just find an old one.
echo "Cleaning up old surveys..."
# Using python script for API interaction if needed, or raw SQL
docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -e "
DELETE FROM lime_surveys WHERE sid IN (
    SELECT surveyls_survey_id FROM lime_surveys_languagesettings 
    WHERE surveyls_title LIKE '%SaaS%' OR surveyls_title LIKE '%Pricing%'
);" 2>/dev/null || true

# Record initial survey count
INITIAL_COUNT=$(get_survey_count)
echo "$INITIAL_COUNT" > /tmp/initial_survey_count
echo "Initial survey count: $INITIAL_COUNT"

# Ensure Firefox is focused on LimeSurvey admin
echo "Focusing Firefox..."
focus_firefox
# Navigate to admin home to ensure clean start
DISPLAY=:1 xdotool type "http://localhost/index.php/admin"
DISPLAY=:1 xdotool key Return
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
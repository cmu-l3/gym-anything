#!/bin/bash
echo "=== Setting up IT Asset Inventory Validation Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Record initial survey count to detect new creations
INITIAL_SURVEY_COUNT=$(get_survey_count)
echo "$INITIAL_SURVEY_COUNT" > /tmp/initial_survey_count.txt

# Ensure Firefox is running and focused on LimeSurvey admin
echo "Ensuring Firefox is running..."
focus_firefox

# Navigate to LimeSurvey admin if not already there
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool type "http://localhost/index.php/admin"
DISPLAY=:1 xdotool key Return
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Agent must create survey 'IT Asset Audit 2025' with specific regex and logic validation."
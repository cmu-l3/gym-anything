#!/bin/bash
echo "=== Setting up Insurance Claims Upload Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Ensure LimeSurvey is running and ready
echo "Checking LimeSurvey status..."
wait_for_page_load 5

# Clean up any previous attempts to ensure a fresh start
# We delete any survey containing "Insurance Claim" in the title
echo "Cleaning up previous surveys..."
limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%Insurance Claim%'"
limesurvey_query "DELETE FROM lime_surveys WHERE sid NOT IN (SELECT surveyls_survey_id FROM lime_surveys_languagesettings)"

# Record start time
date +%s > /tmp/task_start_time.txt

# Record initial survey count
INITIAL_COUNT=$(get_survey_count)
echo "$INITIAL_COUNT" > /tmp/initial_survey_count

# Ensure Firefox is focused on LimeSurvey admin
echo "Launching Firefox..."
focus_firefox
# Navigate to admin home to ensure clean state
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool type "http://localhost/index.php/admin"
DISPLAY=:1 xdotool key Return
sleep 3

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Agent Instructions:"
echo "1. Login (admin/Admin123!)"
echo "2. Create survey: 'Auto Insurance Claim Portal 2025'"
echo "3. Group 'Incident Details': Question 'HAS_EVIDENCE' (Yes/No)"
echo "4. Group 'Document Submission':"
echo "   - 'FORM_PDF' (File Upload): PDF only, Max 1 file"
echo "   - 'DMG_PHOTOS' (File Upload): JPG/PNG only, Max 5 files"
echo "   - DMG_PHOTOS must have condition: Only show if HAS_EVIDENCE == Yes"
echo "5. Activate survey"
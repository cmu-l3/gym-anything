#!/bin/bash
echo "=== Setting up analyst_ehr_uml_design task ==="

source /workspace/scripts/task_utils.sh

# Kill any running EdrawMax instances
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Remove any leftover output file from previous runs
rm -f /home/ga/ehr_uml_design.eddx 2>/dev/null || true

# Record task start timestamp AFTER cleanup
date +%s > /tmp/analyst_ehr_uml_design_start_ts

# Launch EdrawMax fresh (opens to home/new screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take a screenshot to verify start state
sleep 2
take_screenshot /tmp/analyst_ehr_uml_design_start.png
echo "Start state screenshot saved to /tmp/analyst_ehr_uml_design_start.png"

echo "=== analyst_ehr_uml_design task setup complete ==="
echo "EdrawMax is open. Agent should create a 3-page EHR UML design and save as /home/ga/ehr_uml_design.eddx"

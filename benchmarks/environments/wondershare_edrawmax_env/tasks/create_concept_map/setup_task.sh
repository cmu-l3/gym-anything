#!/bin/bash
set -e
echo "=== Setting up create_concept_map task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -f /home/ga/Documents/ehr_concept_map.eddx 2>/dev/null || true
rm -f /home/ga/Documents/ehr_concept_map.png 2>/dev/null || true

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Kill any existing EdrawMax instances
kill_edrawmax

# Launch EdrawMax fresh (opens to home/start screen)
echo "Launching EdrawMax..."
launch_edrawmax
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Banner)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Additional wait for the app to settle
sleep 5

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "EdrawMax is open and ready. Agent should create the concept map."
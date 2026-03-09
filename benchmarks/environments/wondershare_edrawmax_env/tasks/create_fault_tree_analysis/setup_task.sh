#!/bin/bash
echo "=== Setting up create_fault_tree_analysis task ==="

source /workspace/scripts/task_utils.sh

# 1. Kill any running EdrawMax instances to ensure clean state
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# 2. Clean up previous run artifacts
rm -f /home/ga/Documents/fta_db_failure.eddx 2>/dev/null || true
rm -f /home/ga/Documents/fta_db_failure.png 2>/dev/null || true

# 3. Create Documents directory if it doesn't exist
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 4. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 5. Launch EdrawMax fresh (opens to home/template selection screen)
echo "Launching EdrawMax..."
launch_edrawmax

# 6. Wait for EdrawMax to fully load
# EdrawMax is heavy, give it time
wait_for_edrawmax 90

# 7. Dismiss startup dialogs (Account Login, File Recovery, promotional banners)
dismiss_edrawmax_dialogs

# 8. Maximize the window for VLM visibility
maximize_edrawmax

# 9. Take a screenshot to verify start state
take_screenshot /tmp/task_initial.png
echo "Start state screenshot saved to /tmp/task_initial.png"

echo "=== create_fault_tree_analysis task setup complete ==="
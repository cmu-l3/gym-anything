#!/bin/bash
echo "=== Setting up create_org_chart task ==="

source /workspace/scripts/task_utils.sh

# Kill any running EdrawMax instances
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Remove any leftover output files from previous runs
rm -f /home/ga/apache_org_chart.eddx 2>/dev/null || true

# Launch EdrawMax fresh (no file argument - opens to home/editor screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login and File Recovery)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take a screenshot to verify start state
take_screenshot /tmp/create_org_chart_start.png
echo "Start state screenshot saved to /tmp/create_org_chart_start.png"

echo "=== create_org_chart task setup complete ==="
echo "EdrawMax is open. Agent should create a new Org Chart diagram and save as /home/ga/apache_org_chart.eddx"

#!/bin/bash
set -e
echo "=== Setting up create_hvac_plan task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous run artifacts
rm -f /home/ga/Documents/server_room_hvac.eddx 2>/dev/null || true
rm -f /home/ga/Documents/server_room_hvac.png 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# 3. Ensure EdrawMax is running cleanly
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

echo "Launching EdrawMax..."
# Launch without arguments to land on Home/New screen
launch_edrawmax

# 4. Wait for application to be ready
# Large Java/Qt apps take time to initialize
wait_for_edrawmax 90

# 5. Handle initial dialogs (Sign-in, Recovery)
dismiss_edrawmax_dialogs

# 6. Maximize for visibility
maximize_edrawmax

# 7. Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved."

echo "=== Task setup complete ==="
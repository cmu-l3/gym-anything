#!/bin/bash
echo "=== Setting up create_data_flow_diagram task ==="

source /workspace/scripts/task_utils.sh

# 1. Kill any running EdrawMax instances to ensure a clean start
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# 2. Clean up previous task artifacts
echo "Cleaning up previous output files..."
rm -f /home/ga/Diagrams/dfd_context_diagram.eddx 2>/dev/null || true
rm -f /home/ga/Diagrams/dfd_context_diagram.png 2>/dev/null || true
mkdir -p /home/ga/Diagrams

# 3. Record task start time for anti-gaming verification
# (Files created before this time will be rejected)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 4. Launch EdrawMax to the Home/New screen (no specific file loaded)
echo "Launching EdrawMax..."
launch_edrawmax

# 5. Wait for EdrawMax UI to fully load
wait_for_edrawmax 90

# 6. Dismiss startup dialogs (Account Login, File Recovery, Banners)
dismiss_edrawmax_dialogs

# 7. Maximize the window for the agent
maximize_edrawmax

# 8. Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot captured: /tmp/task_initial.png"

echo "=== Task setup complete ==="
#!/bin/bash
echo "=== Setting up create_fashion_sketch task ==="

source /workspace/scripts/task_utils.sh

# 1. Kill any running instances to ensure clean state
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# 2. Clean up previous run artifacts
rm -f /home/ga/Documents/uniform_spec.eddx 2>/dev/null || true
rm -f /home/ga/Documents/uniform_spec.png 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# 3. Record start time for anti-gaming (timestamp verification)
date +%s > /tmp/task_start_time.txt

# 4. Launch EdrawMax to the Home/New screen
echo "Launching EdrawMax..."
launch_edrawmax

# 5. Wait for application to be ready
wait_for_edrawmax 90

# 6. specific setup for this task:
# Ensure the "Fashion Design" libraries are accessible implies standard setup is enough.
# We just need to make sure the app is usable.

# 7. Dismiss popups
dismiss_edrawmax_dialogs

# 8. Maximize window
maximize_edrawmax

# 9. Initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo "=== Setup complete ==="
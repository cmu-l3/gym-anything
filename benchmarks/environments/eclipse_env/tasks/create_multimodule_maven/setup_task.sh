#!/bin/bash
set -e
echo "=== Setting up create_multimodule_maven task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure clean state: Remove any existing project with the target name
echo "Cleaning workspace..."
rm -rf /home/ga/eclipse-workspace/toolkit-parent 2>/dev/null || true
rm -rf /home/ga/eclipse-workspace/toolkit-core 2>/dev/null || true
rm -rf /home/ga/eclipse-workspace/toolkit-app 2>/dev/null || true

# Wait for Eclipse to be ready
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Focus and maximize Eclipse window
focus_eclipse_window
sleep 2

# Dismiss any dialogs (welcome, tips)
dismiss_dialogs 3

# Close welcome tab if present
close_welcome_tab

# Ensure Java perspective is active (optional, but good practice)
# We rely on the agent to handle perspective switching if needed, 
# but starting clean is important.

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
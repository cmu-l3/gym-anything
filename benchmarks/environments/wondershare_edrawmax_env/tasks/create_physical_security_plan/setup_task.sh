#!/bin/bash
echo "=== Setting up create_physical_security_plan task ==="

source /workspace/scripts/task_utils.sh

# 1. Kill any running EdrawMax instances to ensure clean state
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# 2. Prepare directories
mkdir -p /home/ga/Diagrams
# Clean up previous run artifacts
rm -f /home/ga/Diagrams/security_plan.eddx 2>/dev/null || true
rm -f /home/ga/Diagrams/security_plan.png 2>/dev/null || true

# 3. Record task start time for anti-gaming (file timestamp checks)
date +%s > /tmp/task_start_time.txt

# 4. Launch EdrawMax (no file argument -> opens Home/New screen)
# The agent must navigate to "Building Plan" -> "Security and Access Control" themselves
echo "Launching EdrawMax..."
launch_edrawmax

# 5. Wait for application to load
wait_for_edrawmax 90

# 6. Dismiss startup dialogs (Account Login, Recovery, etc.)
dismiss_edrawmax_dialogs

# 7. Maximize window (Critical for seeing the library sidebars)
maximize_edrawmax

# 8. Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="
#!/bin/bash
echo "=== Setting up OpenICE Test Suite Execution Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Ensure OpenICE Supervisor is running (context for the task)
ensure_openice_running

# Maximize OpenICE window
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Prepare the project directory
PROJECT_ROOT="/opt/openice/mdpnp"
if [ ! -d "$PROJECT_ROOT" ]; then
    echo "Error: Project root not found at $PROJECT_ROOT"
    exit 1
fi

# CRITICAL: Clean up ANY previous test results to ensure the agent actually runs them
# We want to force the agent to generate NEW artifacts
echo "Cleaning previous test results..."
find "$PROJECT_ROOT" -name "test-results" -type d -exec rm -rf {} + 2>/dev/null || true
find "$PROJECT_ROOT" -name "reports" -type d -exec rm -rf {} + 2>/dev/null || true
rm -f /home/ga/Desktop/test_execution_report.txt 2>/dev/null || true

# Open a terminal for the agent to use
# The task requires command line interaction
echo "Opening terminal for agent..."
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=$PROJECT_ROOT" &
sleep 2

# Maximize terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="
echo "Project root: $PROJECT_ROOT"
echo "Previous test artifacts cleaned."
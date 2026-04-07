#!/bin/bash
echo "=== Setting up add_arch_design_section task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any running ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Create a fresh task project copy to ensure clean state
# The setup_task_project util copies the example project to the specified name
PROJECT_PATH=$(setup_task_project "add_arch_design_section")
echo "$PROJECT_PATH" > /tmp/task_project_path.txt
echo "Task project path: $PROJECT_PATH"

# Record initial state of ARCH.json for comparison
# Note: Filename might be ARCH.json or lower case depending on version, usually ARCH.json in example
ARCH_JSON="$PROJECT_PATH/documents/ARCH.json"
if [ -f "$ARCH_JSON" ]; then
    cp "$ARCH_JSON" "/tmp/ARCH_initial.json"
    stat -c %Y "$ARCH_JSON" > /tmp/arch_initial_mtime.txt
else
    echo "WARNING: ARCH.json not found at expected path: $ARCH_JSON"
fi

# Launch ReqView with the project
# This opens the project but usually starts with no document open or the last open one
launch_reqview_with_project "$PROJECT_PATH"

# Wait for window to settle
sleep 5

# Dismiss any startup dialogs
dismiss_dialogs

# Maximize window for better agent visibility
maximize_window

# NOTE: We intentionally do NOT open the ARCH document here.
# Navigating to the ARCH document is part of the task (Step 1).

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
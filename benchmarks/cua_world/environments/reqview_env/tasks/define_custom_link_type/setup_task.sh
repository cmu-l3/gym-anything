#!/bin/bash
echo "=== Setting up define_custom_link_type task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project for this specific task
# We use a specific name 'define_link_type_project' to isolate it
PROJECT_PATH=$(setup_task_project "define_link_type")
echo "Task project path: $PROJECT_PATH"

# Ensure the RISKS document exists (it should in the example project)
RISKS_PATH="$PROJECT_PATH/documents/RISKS.json"
if [ ! -f "$RISKS_PATH" ]; then
    echo "WARNING: RISKS document not found at $RISKS_PATH. Task may be impossible."
fi

# Record initial file timestamp to detect modifications later
if [ -f "$PROJECT_PATH/project.json" ]; then
    stat -c %Y "$PROJECT_PATH/project.json" > /tmp/initial_project_mtime.txt
else
    echo "0" > /tmp/initial_project_mtime.txt
fi

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

sleep 5

# Dismiss any startup dialogs
dismiss_dialogs

# Maximize window
maximize_window

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== define_custom_link_type setup complete ==="
#!/bin/bash
set -e
echo "=== Setting up export_diagram_formats task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Clean up any previous exports
rm -rf /home/ga/Documents/exports
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports
echo "Export directory created: ~/Documents/exports/"

# Kill any running EdrawMax instances
kill_edrawmax
sleep 2

# Find a template .eddx file to open
# Use find_template from task_utils or fallback
TEMPLATE_FILE=$(find_template "flowchart")

if [ -z "$TEMPLATE_FILE" ] || [ ! -f "$TEMPLATE_FILE" ]; then
    # Broader search in /opt
    TEMPLATE_FILE=$(find /opt -name "*.eddx" -type f 2>/dev/null | head -1)
fi

if [ -z "$TEMPLATE_FILE" ] || [ ! -f "$TEMPLATE_FILE" ]; then
    echo "ERROR: No .eddx template file found for the task"
    exit 1
fi

echo "Using template: $TEMPLATE_FILE"

# Copy template to a working location so the agent has a clean file
WORK_FILE="/home/ga/Documents/working_diagram.eddx"
cp "$TEMPLATE_FILE" "$WORK_FILE"
chown ga:ga "$WORK_FILE"
echo "Working diagram: $WORK_FILE"

# Launch EdrawMax with the diagram file
echo "Launching EdrawMax with diagram..."
launch_edrawmax "$WORK_FILE"

# Wait for EdrawMax to start and load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, notification banners)
dismiss_edrawmax_dialogs

# Maximize the EdrawMax window
maximize_edrawmax
sleep 3

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png
echo "Initial screenshot saved to /tmp/task_initial_state.png"

echo ""
echo "=== Task setup complete ==="
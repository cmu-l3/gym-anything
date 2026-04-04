#!/bin/bash
echo "=== Setting up apply_theme task ==="

source /workspace/scripts/task_utils.sh

# Kill any running EdrawMax instances
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Remove any leftover output files from previous runs
rm -f /home/ga/themed_flowchart.eddx 2>/dev/null || true

# Use the bundled flowchart_en.eddx from data/ mount (primary), then installation fallback
TEMPLATE=""

# Primary: bundled real template from /workspace/data/
if [ -f "/workspace/data/flowchart_en.eddx" ]; then
    TEMPLATE="/workspace/data/flowchart_en.eddx"
    echo "Using bundled template from /workspace/data/"
fi

# Fallback 1: copied to ~/Diagrams/ during post_start
if [ -z "$TEMPLATE" ]; then
    TEMPLATE=$(find /home/ga/Diagrams -name "flowchart_en.eddx" -type f 2>/dev/null | head -1)
fi

# Fallback 2: directly from EdrawMax installation (confirmed path in v15.0.6)
if [ -z "$TEMPLATE" ]; then
    TEMPLATE="/opt/apps/edrawmax/config/aiexample/flowchart_en.eddx"
    if [ ! -f "$TEMPLATE" ]; then
        TEMPLATE=$(find /opt/apps/edrawmax -name "flowchart_en.eddx" 2>/dev/null | head -1)
    fi
fi

# Fallback 3: any .eddx from installation
if [ -z "$TEMPLATE" ] || [ ! -f "$TEMPLATE" ]; then
    TEMPLATE=$(find /opt -name "*.eddx" -type f 2>/dev/null | head -1)
fi

if [ -z "$TEMPLATE" ] || [ ! -f "$TEMPLATE" ]; then
    echo "ERROR: No EdrawMax template (.eddx) files found."
    echo "Searched: /workspace/data/, ~/Diagrams/, /opt/apps/edrawmax/, /opt/"
    exit 1
fi

echo "Using template: $TEMPLATE"

# Copy the flowchart template as the task file
TASK_FILE="/home/ga/flowchart_task.eddx"
cp "$TEMPLATE" "$TASK_FILE"
chown ga:ga "$TASK_FILE"
echo "Task diagram file: $TASK_FILE"

# Launch EdrawMax with the flowchart template file open
echo "Launching EdrawMax with flowchart template..."
launch_edrawmax "$TASK_FILE"

# Wait for EdrawMax to fully load with the file
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login and File Recovery)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take a screenshot to verify start state
take_screenshot /tmp/apply_theme_start.png
echo "Start state screenshot saved to /tmp/apply_theme_start.png"

echo "=== apply_theme task setup complete ==="
echo "EdrawMax is open with $TASK_FILE (flowchart). Agent should apply the 'Warm' color theme via Design > Color dropdown and save as /home/ga/themed_flowchart.eddx"

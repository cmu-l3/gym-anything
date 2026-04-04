#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up mirror_bracket_assembly task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure clean state
rm -f /home/ga/Documents/FreeCAD/symmetric_bracket_assembly.FCStd

# Ensure input file exists
INPUT_FILE="/home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd"
if [ ! -f "$INPUT_FILE" ]; then
    echo "Restoring input file from samples..."
    cp /opt/freecad_samples/T8_housing_bracket.FCStd "$INPUT_FILE"
    chown ga:ga "$INPUT_FILE"
fi

# Record original file size for comparison later
stat -c%s "$INPUT_FILE" > /tmp/original_file_size.txt

# Kill any running FreeCAD instance
kill_freecad

# Launch FreeCAD with the T8 housing bracket loaded
echo "Launching FreeCAD with T8 bracket..."
launch_freecad "$INPUT_FILE"

# Wait for FreeCAD window
wait_for_freecad 45

# Give extra time for file loading and 3D view rendering
sleep 5

# Maximize window (CRITICAL for agent visibility)
maximize_freecad

# Ensure Part workbench is active (though user preference might override, we try to set context)
# We can't easily force workbench via CLI args without a script, but the task description
# tells the agent what to do. The file load should trigger PartDesign or Part.

# Dismiss any startup dialogs if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
#!/bin/bash
set -e
echo "=== Setting up create_techdraw task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Define paths
DOCS_DIR="/home/ga/Documents/FreeCAD"
INPUT_FILE="$DOCS_DIR/T8_housing_bracket.FCStd"
OUTPUT_FCSTD="$DOCS_DIR/T8_bracket_drawing.FCStd"
OUTPUT_PDF="$DOCS_DIR/T8_bracket_drawing.pdf"

# Ensure Documents directory exists and is clean
mkdir -p "$DOCS_DIR"
rm -f "$OUTPUT_FCSTD"
rm -f "$OUTPUT_PDF"

# Copy the real input model from system samples to user docs
# T8_housing_bracket.FCStd is a real part provided by the environment
if [ -f "/opt/freecad_samples/T8_housing_bracket.FCStd" ]; then
    cp /opt/freecad_samples/T8_housing_bracket.FCStd "$INPUT_FILE"
    echo "Copied input model to $INPUT_FILE"
else
    # Fallback if specific file missing (should not happen in correct env)
    echo "WARNING: Sample file not found in /opt, checking local..."
    if [ ! -f "$INPUT_FILE" ]; then
        echo "ERROR: T8_housing_bracket.FCStd not found anywhere."
        exit 1
    fi
fi

# Set permissions
chown -R ga:ga "$DOCS_DIR"

# Kill any existing FreeCAD instance
kill_freecad

# Launch FreeCAD with the bracket model pre-loaded
echo "Launching FreeCAD..."
launch_freecad "$INPUT_FILE"

# Wait for FreeCAD window to appear (can take a moment for GUI)
wait_for_freecad 60

# Wait extra time for the model file to fully load and render
sleep 5

# Maximize the window to ensure all toolbars are visible
maximize_freecad

# Focus the window
DISPLAY=:1 wmctrl -a "FreeCAD" 2>/dev/null || true

# Dismiss any startup dialogs/popups if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== create_techdraw setup complete ==="
#!/bin/bash
echo "=== Setting up Load Sample Data task ==="

source /workspace/scripts/task_utils.sh

# Ensure sample data exists
SAMPLE_DIR=$(get_sample_data_dir)
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"

if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Warning: Sample file not found at $SAMPLE_FILE"
    echo "Attempting to download..."
    mkdir -p "$SAMPLE_DIR"
    wget -q -O "$SAMPLE_FILE" "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null || \
        echo "Could not download sample data"
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

# Record initial state
SCREENSHOT_DIR=$(get_slicer_screenshot_dir)
mkdir -p "$SCREENSHOT_DIR"
INITIAL_SCREENSHOT_COUNT=$(ls -1 "$SCREENSHOT_DIR"/*.png 2>/dev/null | wc -l)
echo "$INITIAL_SCREENSHOT_COUNT" > /tmp/initial_screenshot_count

# Clean any previous task results
rm -f /tmp/slicer_task_result.json 2>/dev/null || true

# Launch 3D Slicer (without loading the file - agent needs to do that)
echo "Launching 3D Slicer..."
launch_slicer_with_file "" ga

# Dismiss any first-run dialogs and maximize window
echo "Configuring Slicer window..."
sleep 2

# Focus and maximize the Slicer window
WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"

    # Maximize the window for better agent interaction
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Press Escape to close any dialogs, then Enter to confirm
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1

# Re-focus and ensure maximized
WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi
sleep 1

# Take initial screenshot to record starting state
take_screenshot /tmp/slicer_initial.png ga

echo "Sample file location: $SAMPLE_FILE"
echo "Initial screenshot count: $INITIAL_SCREENSHOT_COUNT"
echo "=== Task setup complete ==="
echo ""
echo "TASK: Load the MRHead.nrrd file from ~/Documents/SlicerData/SampleData/ into 3D Slicer"
echo "      and verify the brain scan is visible in the slice views."

#!/bin/bash
echo "=== Setting up Record Slice Animation Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Create exports directory
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
mkdir -p "$EXPORTS_DIR"
chown -R ga:ga "$EXPORTS_DIR" 2>/dev/null || true

# Remove any pre-existing output file to ensure fresh creation
OUTPUT_PATH="$EXPORTS_DIR/brain_axial_sweep.gif"
if [ -f "$OUTPUT_PATH" ]; then
    echo "Removing pre-existing output file..."
    rm -f "$OUTPUT_PATH"
fi

# Record initial state - check for any existing GIF files
INITIAL_GIF_COUNT=$(ls -1 "$EXPORTS_DIR"/*.gif 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_GIF_COUNT" > /tmp/initial_gif_count.txt
ls -la "$EXPORTS_DIR"/*.gif 2>/dev/null > /tmp/initial_gif_list.txt || true

# Verify sample data exists
SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"

if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Sample file not found, downloading..."
    mkdir -p "$SAMPLE_DIR"
    # Try primary URL
    curl -L -o "$SAMPLE_FILE" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null || \
    # Fallback URL
    wget -O "$SAMPLE_FILE" --timeout=120 \
        "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || \
    echo "WARNING: Could not download sample data"
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

# Verify sample file exists and has content
if [ -f "$SAMPLE_FILE" ]; then
    SAMPLE_SIZE=$(stat -c %s "$SAMPLE_FILE" 2>/dev/null || echo "0")
    echo "Sample file: $SAMPLE_FILE ($SAMPLE_SIZE bytes)"
else
    echo "ERROR: Sample file not found at $SAMPLE_FILE"
fi

# Kill any existing Slicer instances for clean start
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with the sample data pre-loaded
echo "Launching 3D Slicer with MRHead data..."
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$SAMPLE_FILE' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start and data to load
echo "Waiting for 3D Slicer to start and load data..."
sleep 10

# Wait for Slicer window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer\|3D Slicer\|MRHead"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait additional time for data to fully load
echo "Waiting for data to fully load..."
sleep 10

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Verify data loaded by checking window title
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
echo "Active window title: $WINDOW_TITLE"

if echo "$WINDOW_TITLE" | grep -qi "MRHead\|Slicer"; then
    echo "Data appears to be loaded"
    DATA_LOADED="true"
else
    echo "Warning: Cannot confirm data loaded from window title"
    DATA_LOADED="uncertain"
fi

# Save initial state info
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_gif_count": $INITIAL_GIF_COUNT,
    "sample_file_exists": $([ -f "$SAMPLE_FILE" ] && echo "true" || echo "false"),
    "sample_file_size": $(stat -c %s "$SAMPLE_FILE" 2>/dev/null || echo "0"),
    "data_loaded": "$DATA_LOADED",
    "window_title": "$WINDOW_TITLE",
    "exports_dir": "$EXPORTS_DIR",
    "expected_output": "$OUTPUT_PATH"
}
EOF

echo "Initial state saved:"
cat /tmp/initial_state.json

# Take initial screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    INIT_SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: $INIT_SIZE bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Create an animated GIF of the brain MRI slice sweep"
echo ""
echo "Instructions:"
echo "  1. Open Screen Capture module (search 'Screen Capture' or Modules > Utilities > Screen Capture)"
echo "  2. Set Master view to 'Red' (axial view)"
echo "  3. Set Animation mode to 'slice sweep'"
echo "  4. Set output path to: $OUTPUT_PATH"
echo "  5. Click 'Capture' to generate the animation"
echo ""
echo "The MRHead brain MRI is already loaded and visible."
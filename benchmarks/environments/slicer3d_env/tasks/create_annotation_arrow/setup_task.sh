#!/bin/bash
echo "=== Setting up Create Annotation Arrow Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
EXPECTED_SCREENSHOT="$SCREENSHOT_DIR/ventricle_annotation.png"

# Create directories
mkdir -p "$SAMPLE_DIR"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Ensure sample data exists
if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Downloading MRHead sample data..."
    wget -q -O "$SAMPLE_FILE" \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null || \
    curl -L -o "$SAMPLE_FILE" \
        "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || \
    echo "WARNING: Could not download sample data"
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

# Verify sample file exists and has content
if [ -f "$SAMPLE_FILE" ]; then
    SAMPLE_SIZE=$(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo "0")
    echo "Sample file: $SAMPLE_FILE ($SAMPLE_SIZE bytes)"
    if [ "$SAMPLE_SIZE" -lt 1000000 ]; then
        echo "WARNING: Sample file may be incomplete"
    fi
else
    echo "ERROR: Sample file not found at $SAMPLE_FILE"
fi

# Record initial state
rm -f /tmp/annotation_task_result.json 2>/dev/null || true
rm -f "$EXPECTED_SCREENSHOT" 2>/dev/null || true

# Record initial screenshot count
INITIAL_SCREENSHOT_COUNT=$(ls -1 "$SCREENSHOT_DIR"/*.png 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_SCREENSHOT_COUNT" > /tmp/initial_screenshot_count.txt

# List existing screenshots for comparison
ls -la "$SCREENSHOT_DIR"/*.png 2>/dev/null > /tmp/initial_screenshots_list.txt || touch /tmp/initial_screenshots_list.txt

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with the MRHead sample pre-loaded
echo "Launching 3D Slicer with MRHead data..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Start Slicer as ga user with the data file
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$SAMPLE_FILE' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
for i in {1..60}; do
    if pgrep -f "Slicer" > /dev/null 2>&1; then
        # Check for window
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer\|3D Slicer"; then
            echo "3D Slicer window detected"
            break
        fi
    fi
    sleep 2
done

# Wait additional time for data to load
echo "Waiting for data to load..."
sleep 10

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Verify data loaded by checking window title or via Python
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "")
echo "Active window: $WINDOW_TITLE"

if echo "$WINDOW_TITLE" | grep -qi "MRHead\|Slicer"; then
    echo "Slicer appears ready with data"
else
    echo "WARNING: Could not confirm data loaded"
fi

# Take initial screenshot for evidence
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c%s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Create an annotation arrow pointing to the left lateral ventricle"
echo ""
echo "Instructions:"
echo "  1. Navigate through AXIAL slices to find the lateral ventricles"
echo "     (dark CSF-filled regions in the center of the brain)"
echo "  2. Create an arrow annotation using Markups module"
echo "  3. Point the arrow TIP at the LEFT lateral ventricle"
echo "  4. Label the arrow 'Left Lateral Ventricle'"
echo "  5. Save a screenshot to: $EXPECTED_SCREENSHOT"
echo ""
echo "Sample data: $SAMPLE_FILE"
echo "Screenshot output: $EXPECTED_SCREENSHOT"
#!/bin/bash
echo "=== Setting up Annotate Findings Report Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure directories exist
SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
mkdir -p "$SAMPLE_DIR"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Ensure sample data exists
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"
if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Downloading MRHead sample data..."
    # Try multiple sources
    wget -q -O "$SAMPLE_FILE" \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null || \
    curl -L -o "$SAMPLE_FILE" \
        "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || true
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

# Verify sample data exists
if [ ! -f "$SAMPLE_FILE" ]; then
    echo "ERROR: Sample data not available at $SAMPLE_FILE"
    exit 1
fi
echo "Sample data verified: $SAMPLE_FILE ($(du -h "$SAMPLE_FILE" | cut -f1))"

# Record initial state - no markups should exist
echo "Recording initial state..."
cat > /tmp/initial_markup_state.json << 'EOF'
{
    "line_markups_count": 0,
    "text_markups_count": 0,
    "fiducial_markups_count": 0,
    "screenshots_in_dir": 0
}
EOF

# Count existing screenshots
INITIAL_SCREENSHOT_COUNT=$(ls -1 "$SCREENSHOT_DIR"/*.png 2>/dev/null | wc -l || echo "0")
echo "Initial screenshot count: $INITIAL_SCREENSHOT_COUNT"
echo "$INITIAL_SCREENSHOT_COUNT" > /tmp/initial_screenshot_count.txt

# Clean any previous task outputs
rm -f /tmp/annotation_task_result.json 2>/dev/null || true
rm -f "$SCREENSHOT_DIR/annotated_cc_report.png" 2>/dev/null || true

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with the sample data
echo "Launching 3D Slicer with MRHead..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Launch Slicer with data file
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$SAMPLE_FILE' > /tmp/slicer_launch.log 2>&1 &"

echo "Waiting for 3D Slicer to start and load data..."
sleep 10

# Wait for Slicer window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer\|3D Slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait additional time for data to fully load
sleep 5

# Maximize and focus Slicer window
echo "Maximizing and focusing Slicer window..."
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Navigate to sagittal view using keyboard shortcuts
# In Slicer, we can use the layout selector or switch views
echo "Configuring view for sagittal slice..."

# Take initial screenshot showing the loaded data
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    INITIAL_SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: $INITIAL_SIZE bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Create an annotated clinical image"
echo ""
echo "Instructions:"
echo "1. Navigate to SAGITTAL view (Yellow slice) showing the corpus callosum"
echo "2. Go to slice ~128 where corpus callosum is most visible"
echo "3. Open Markups module and create a LINE/ruler measuring the corpus callosum"
echo "4. Create a TEXT annotation with label 'Corpus Callosum - Normal'"
echo "5. Save screenshot to: ~/Documents/SlicerData/Screenshots/annotated_cc_report.png"
echo ""
echo "Sample data: $SAMPLE_FILE"
echo "Screenshot save location: $SCREENSHOT_DIR/annotated_cc_report.png"
echo ""
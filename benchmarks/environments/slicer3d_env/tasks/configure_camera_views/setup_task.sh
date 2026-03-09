#!/bin/bash
echo "=== Setting up Configure Camera Views Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Define paths
SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"

# Create required directories
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

# Verify sample file
if [ -f "$SAMPLE_FILE" ]; then
    SAMPLE_SIZE=$(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo "0")
    echo "Sample file exists: $SAMPLE_FILE ($SAMPLE_SIZE bytes)"
else
    echo "ERROR: Sample file not found at $SAMPLE_FILE"
fi

# Record initial screenshot state
INITIAL_ANTERIOR="false"
INITIAL_LATERAL="false"
INITIAL_SUPERIOR="false"

[ -f "$SCREENSHOT_DIR/anterior_view.png" ] && INITIAL_ANTERIOR="true"
[ -f "$SCREENSHOT_DIR/lateral_view.png" ] && INITIAL_LATERAL="true"
[ -f "$SCREENSHOT_DIR/superior_view.png" ] && INITIAL_SUPERIOR="true"

cat > /tmp/initial_screenshot_state.json << EOF
{
    "anterior_existed": $INITIAL_ANTERIOR,
    "lateral_existed": $INITIAL_LATERAL,
    "superior_existed": $INITIAL_SUPERIOR,
    "task_start_time": $(date +%s)
}
EOF

echo "Initial screenshot state recorded"

# Remove any existing screenshots (to ensure fresh creation)
rm -f "$SCREENSHOT_DIR/anterior_view.png" 2>/dev/null || true
rm -f "$SCREENSHOT_DIR/lateral_view.png" 2>/dev/null || true
rm -f "$SCREENSHOT_DIR/superior_view.png" 2>/dev/null || true

# Clean any previous task results
rm -f /tmp/camera_views_result.json 2>/dev/null || true

# Kill any existing Slicer instances for clean start
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with the sample data pre-loaded
echo "Launching 3D Slicer with MRHead data..."

# Start Slicer as ga user
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$SAMPLE_FILE' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
for i in {1..60}; do
    if pgrep -f "Slicer" > /dev/null 2>&1; then
        WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "slicer\|3D Slicer" | head -1 | awk '{print $1}')
        if [ -n "$WID" ]; then
            echo "3D Slicer window detected"
            break
        fi
    fi
    sleep 2
done

# Wait for data to load
echo "Waiting for data to load..."
sleep 10

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot showing data loaded
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Configure 3D camera views and capture screenshots"
echo ""
echo "Sample data: $SAMPLE_FILE"
echo "Screenshot directory: $SCREENSHOT_DIR"
echo ""
echo "Required screenshots:"
echo "  1. anterior_view.png - Front view of brain (looking at face)"
echo "  2. lateral_view.png - Right side view (profile)"
echo "  3. superior_view.png - Top-down view (looking at crown)"
echo ""
echo "Steps:"
echo "  1. Go to Volume Rendering module"
echo "  2. Enable volume rendering (click eye icon)"
echo "  3. Rotate 3D view to anterior position, capture screenshot"
echo "  4. Rotate to lateral position, capture screenshot"
echo "  5. Rotate to superior position, capture screenshot"
echo ""
#!/bin/bash
echo "=== Setting up Export Landmarks to CSV task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Paths
SAMPLE_FILE="/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_CSV="$EXPORTS_DIR/landmarks.csv"

# Create exports directory
echo "Creating exports directory..."
mkdir -p "$EXPORTS_DIR"
chown -R ga:ga "$EXPORTS_DIR" 2>/dev/null || true
chmod 755 "$EXPORTS_DIR"

# Clean any previous task results
rm -f "$OUTPUT_CSV" 2>/dev/null || true
rm -f /tmp/landmarks_task_result.json 2>/dev/null || true
rm -f /tmp/task_initial_state.json 2>/dev/null || true

# Record initial state - no CSV file should exist
echo "Recording initial state..."
cat > /tmp/task_initial_state.json << EOF
{
    "csv_exists": false,
    "csv_path": "$OUTPUT_CSV",
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure sample data exists
if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Sample file not found, downloading..."
    SAMPLE_DIR=$(dirname "$SAMPLE_FILE")
    mkdir -p "$SAMPLE_DIR"
    
    # Try multiple download sources
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

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with the sample file
echo "Launching 3D Slicer with MRHead.nrrd..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Launch Slicer with the sample file loaded
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --no-splash '$SAMPLE_FILE' > /tmp/slicer_launch.log 2>&1" &

echo "Waiting for 3D Slicer to start..."

# Wait for Slicer window to appear
for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer\|3D Slicer"; then
        echo "3D Slicer window detected after ${i}s"
        break
    fi
    sleep 1
done

# Additional wait for data to load
sleep 5

# Wait for data to be loaded (check window title changes)
echo "Waiting for data to load..."
for i in $(seq 1 30); do
    TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "")
    if echo "$TITLE" | grep -qi "MRHead\|Welcome"; then
        echo "Data appears loaded (title: $TITLE)"
        break
    fi
    sleep 1
done

# Maximize and focus Slicer window
echo "Focusing Slicer window..."
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/landmarks_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/landmarks_initial.png 2>/dev/null || true

if [ -f /tmp/landmarks_initial.png ]; then
    INIT_SIZE=$(stat -c%s /tmp/landmarks_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${INIT_SIZE} bytes"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Place fiducial markers on four anatomical landmarks and export to CSV"
echo ""
echo "Landmarks to place:"
echo "  1. AC - Anterior commissure (midline, at anterior third ventricle)"
echo "  2. PC - Posterior commissure (midline, at posterior third ventricle)"
echo "  3. CC_Superior - Most superior point of corpus callosum"
echo "  4. Frontal_Apex - Most anterior point of frontal lobe"
echo ""
echo "Output file: $OUTPUT_CSV"
echo ""
echo "Sample data: $SAMPLE_FILE ($([ -f "$SAMPLE_FILE" ] && echo "loaded" || echo "NOT FOUND"))"
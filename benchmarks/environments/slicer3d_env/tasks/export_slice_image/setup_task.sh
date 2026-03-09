#!/bin/bash
echo "=== Setting up Export Slice Image task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure directories exist
SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"

mkdir -p "$EXPORT_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Check if sample data exists
if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Sample file not found, downloading MRHead.nrrd..."
    mkdir -p "$SAMPLE_DIR"
    
    # Try primary URL
    curl -L -o "$SAMPLE_FILE" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null
    
    # Verify download
    if [ ! -f "$SAMPLE_FILE" ] || [ $(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo 0) -lt 1000000 ]; then
        echo "Primary download failed, trying alternative..."
        wget -O "$SAMPLE_FILE" \
            "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || true
    fi
    
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

# Verify sample file
if [ -f "$SAMPLE_FILE" ]; then
    FILE_SIZE=$(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo "0")
    echo "Sample file: $SAMPLE_FILE ($FILE_SIZE bytes)"
else
    echo "ERROR: Sample file not available at $SAMPLE_FILE"
fi

# Record initial state - check if output file already exists
OUTPUT_PATH="/home/ga/Documents/SlicerData/Exports/ventricles_axial.png"
if [ -f "$OUTPUT_PATH" ]; then
    INITIAL_EXISTS="true"
    INITIAL_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    echo "WARNING: Output file already exists (will check if modified)"
else
    INITIAL_EXISTS="false"
    INITIAL_SIZE="0"
    INITIAL_MTIME="0"
fi

# Save initial state for verification
cat > /tmp/initial_state.json << EOF
{
    "output_exists": $INITIAL_EXISTS,
    "output_size": $INITIAL_SIZE,
    "output_mtime": $INITIAL_MTIME,
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "sample_file": "$SAMPLE_FILE",
    "output_path": "$OUTPUT_PATH"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with the sample file pre-loaded
echo "Launching 3D Slicer with MRHead.nrrd..."
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$SAMPLE_FILE' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to load..."
sleep 8

# Wait for window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait additional time for data to load
echo "Waiting for MRHead data to load..."
sleep 10

# Maximize and focus window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot for evidence
echo "Capturing initial state screenshot..."
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
echo "TASK: Export an axial slice showing the lateral ventricles as a PNG image."
echo ""
echo "Instructions:"
echo "  1. Navigate the axial (red) slice to show both lateral ventricles"
echo "  2. Use Screen Capture module or right-click > Capture to export the view"
echo "  3. Save as: ~/Documents/SlicerData/Exports/ventricles_axial.png"
echo ""
echo "The lateral ventricles are the dark butterfly-shaped cavities in the brain center."
echo "They should be visible at mid-brain level (around slice 130-140)."
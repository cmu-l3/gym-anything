#!/bin/bash
echo "=== Setting up Create Masked Brain Volume Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Define paths
SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"
OUTPUT_PATH="$EXPORT_DIR/MRHead_brain_only.nrrd"

# Ensure directories exist
mkdir -p "$SAMPLE_DIR"
mkdir -p "$EXPORT_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Verify MRHead sample data exists
if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Sample file not found. Attempting to download MRHead.nrrd..."
    
    # Try primary URL
    curl -L -o "$SAMPLE_FILE" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null
    
    # Check if download succeeded
    if [ ! -f "$SAMPLE_FILE" ] || [ "$(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo 0)" -lt 1000000 ]; then
        echo "Primary download failed, trying alternative..."
        curl -L -o "$SAMPLE_FILE" --connect-timeout 30 --max-time 120 \
            "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null
    fi
    
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

# Verify sample file exists and has reasonable size
if [ -f "$SAMPLE_FILE" ]; then
    SAMPLE_SIZE=$(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo "0")
    echo "Sample file found: $SAMPLE_FILE ($(($SAMPLE_SIZE / 1024)) KB)"
    
    if [ "$SAMPLE_SIZE" -lt 1000000 ]; then
        echo "WARNING: Sample file may be corrupted (size < 1MB)"
    fi
else
    echo "ERROR: Could not obtain MRHead.nrrd sample data"
    exit 1
fi

# Record initial state - remove any previous output
if [ -f "$OUTPUT_PATH" ]; then
    echo "Removing previous output file..."
    rm -f "$OUTPUT_PATH"
fi

# Record what files exist before task
ls -la "$EXPORT_DIR"/*.nrrd 2>/dev/null > /tmp/initial_exports_list.txt || echo "No initial exports" > /tmp/initial_exports_list.txt
echo "0" > /tmp/initial_export_count.txt

# Save initial state JSON
cat > /tmp/initial_state.json << EOF
{
    "sample_file_exists": true,
    "sample_file_path": "$SAMPLE_FILE",
    "sample_file_size": $SAMPLE_SIZE,
    "output_path": "$OUTPUT_PATH",
    "output_existed_before": false,
    "task_start_time": $(cat /tmp/task_start_time.txt)
}
EOF
echo "Initial state recorded:"
cat /tmp/initial_state.json

# Kill any existing Slicer instances for clean start
echo "Ensuring clean Slicer state..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer
echo "Launching 3D Slicer..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Start Slicer as ga user
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer > /tmp/slicer_launch.log 2>&1 &
SLICER_PID=$!
echo "Slicer launched with PID: $SLICER_PID"

# Wait for Slicer window to appear
echo "Waiting for 3D Slicer to initialize..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "3D Slicer window detected after ${i}s"
        break
    fi
    sleep 2
done

# Additional wait for full module loading
echo "Waiting for modules to load..."
sleep 10

# Maximize and focus window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Capture initial screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SCREENSHOT_SIZE=$(stat -c%s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SCREENSHOT_SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Create a skull-stripped brain volume"
echo ""
echo "Steps:"
echo "  1. Load MRHead.nrrd from ~/Documents/SlicerData/SampleData/"
echo "  2. Open Segment Editor module"
echo "  3. Create a brain segmentation using Threshold (range: 30-300)"
echo "  4. Use 'Mask volume' effect to create masked output"
echo "  5. Save result to ~/Documents/SlicerData/Exports/MRHead_brain_only.nrrd"
echo ""
echo "Input file: $SAMPLE_FILE"
echo "Expected output: $OUTPUT_PATH"
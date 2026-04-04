#!/bin/bash
echo "=== Setting up Segment Ventricles Task ==="

# Source task utilities
source /workspace/scripts/task_utils.sh

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Create output directory
OUTPUT_DIR="/home/ga/Documents/SlicerData/Exports"
mkdir -p "$OUTPUT_DIR"
chown -R ga:ga "$OUTPUT_DIR"
chmod 755 "$OUTPUT_DIR"

# Remove any previous measurement file (clean state)
rm -f "$OUTPUT_DIR/ventricle_measurement.json" 2>/dev/null || true

# Ensure sample data exists
SAMPLE_DATA="/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd"
if [ ! -f "$SAMPLE_DATA" ]; then
    echo "MRHead sample data not found, downloading..."
    mkdir -p "$(dirname "$SAMPLE_DATA")"
    
    # Try primary URL
    curl -L -o "$SAMPLE_DATA" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null
    
    # Verify download
    if [ ! -f "$SAMPLE_DATA" ] || [ $(stat -c%s "$SAMPLE_DATA" 2>/dev/null || echo 0) -lt 1000000 ]; then
        echo "Primary download failed, trying alternative..."
        curl -L -o "$SAMPLE_DATA" --connect-timeout 30 --max-time 120 \
            "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null
    fi
    
    if [ -f "$SAMPLE_DATA" ] && [ $(stat -c%s "$SAMPLE_DATA" 2>/dev/null || echo 0) -gt 1000000 ]; then
        echo "MRHead downloaded successfully"
        chown ga:ga "$SAMPLE_DATA"
    else
        echo "ERROR: Could not download MRHead sample data"
        exit 1
    fi
fi

echo "Sample data verified: $SAMPLE_DATA ($(du -h "$SAMPLE_DATA" | cut -f1))"

# Record initial state - no segmentations should exist yet
cat > /tmp/initial_scene_state.json << EOF
{
    "task": "segment_ventricles",
    "sample_file": "$SAMPLE_DATA",
    "output_file": "$OUTPUT_DIR/ventricle_measurement.json",
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "timestamp": "$(date -Iseconds)",
    "initial_segmentation_count": 0
}
EOF
echo "Initial state recorded"

# Kill any existing Slicer instances for clean start
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with MRHead data
echo "Launching 3D Slicer with MRHead brain MRI..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Launch as ga user with the data file
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$SAMPLE_DATA' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to fully start
echo "Waiting for 3D Slicer to start..."
wait_for_slicer 120

# Additional wait for data to load
sleep 5

# Maximize and focus Slicer window
SLICER_WID=$(get_slicer_window_id)
if [ -n "$SLICER_WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$SLICER_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$SLICER_WID" 2>/dev/null || true
    echo "Slicer window maximized and focused"
else
    echo "Warning: Could not find Slicer window ID"
fi

# Wait a moment for UI to stabilize
sleep 3

# Take initial screenshot (evidence of starting state)
echo "Capturing initial state screenshot..."
take_screenshot /tmp/task_initial_state.png ga

# Verify screenshot was captured
if [ -f /tmp/task_initial_state.png ]; then
    INITIAL_SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${INITIAL_SIZE} bytes"
else
    echo "Warning: Could not capture initial screenshot"
fi

echo ""
echo "=========================================="
echo "=== Task Setup Complete ==="
echo "=========================================="
echo ""
echo "3D Slicer is running with MRHead brain MRI loaded."
echo ""
echo "TASK: Segment the lateral ventricles and measure their volume"
echo ""
echo "Steps:"
echo "  1. Open Segment Editor module"
echo "  2. Create segment named 'Ventricles'"
echo "  3. Use Threshold to select dark CSF regions"
echo "  4. Refine with Islands/Paint tools"
echo "  5. Use Segment Statistics to measure volume"
echo "  6. Save result to: $OUTPUT_DIR/ventricle_measurement.json"
echo ""
echo "Expected volume: 15-45 mL (valid range: 5-80 mL)"
echo "=========================================="
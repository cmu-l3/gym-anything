#!/bin/bash
echo "=== Setting up Calculate SNR Metric Task ==="

source /workspace/scripts/task_utils.sh

SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"
OUTPUT_DIR="/home/ga/Documents/SlicerData"
OUTPUT_JSON="$OUTPUT_DIR/snr_result.json"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"
chown -R ga:ga "$OUTPUT_DIR" 2>/dev/null || true

# Clean up any previous results
rm -f "$OUTPUT_JSON" 2>/dev/null || true
rm -f /tmp/snr_task_result.json 2>/dev/null || true
rm -f /tmp/snr_initial_state.json 2>/dev/null || true

# Record initial state - no output file should exist
INITIAL_OUTPUT_EXISTS="false"
if [ -f "$OUTPUT_JSON" ]; then
    INITIAL_OUTPUT_EXISTS="true"
fi

# Check sample file exists
SAMPLE_EXISTS="false"
if [ -f "$SAMPLE_FILE" ]; then
    SAMPLE_EXISTS="true"
    echo "Sample file found: $SAMPLE_FILE"
else
    echo "WARNING: Sample file not found at $SAMPLE_FILE"
    echo "Attempting to download..."
    mkdir -p "$SAMPLE_DIR"
    wget -q -O "$SAMPLE_FILE" \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null || \
    curl -L -o "$SAMPLE_FILE" \
        "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || true
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
    if [ -f "$SAMPLE_FILE" ]; then
        SAMPLE_EXISTS="true"
        echo "Sample file downloaded successfully"
    fi
fi

# Save initial state
cat > /tmp/snr_initial_state.json << EOF
{
    "output_exists": $INITIAL_OUTPUT_EXISTS,
    "sample_exists": $SAMPLE_EXISTS,
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "timestamp": "$(date -Iseconds)"
}
EOF
echo "Initial state saved:"
cat /tmp/snr_initial_state.json

# Kill any existing Slicer instances for clean start
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with the sample data pre-loaded
echo "Launching 3D Slicer with MRHead sample..."

if [ -f "$SAMPLE_FILE" ]; then
    su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$SAMPLE_FILE' > /tmp/slicer_launch.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer > /tmp/slicer_launch.log 2>&1 &"
fi

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
sleep 10

# Wait for Slicer window to appear
for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer\|3D Slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Additional wait for modules to load
sleep 5

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/snr_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/snr_initial.png 2>/dev/null || true

if [ -f /tmp/snr_initial.png ]; then
    SIZE=$(stat -c %s /tmp/snr_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Calculate MRI Signal-to-Noise Ratio"
echo ""
echo "The MRHead brain MRI volume should be loaded in Slicer."
echo ""
echo "You need to:"
echo "  1. Go to Segment Editor module"
echo "  2. Create a 'Signal' segment in brain white matter"
echo "  3. Create a 'Noise' segment in background air"
echo "  4. Use Segment Statistics to get mean(Signal) and std(Noise)"
echo "  5. Calculate SNR = mean / std"
echo "  6. Save results to: $OUTPUT_JSON"
echo ""
echo "Expected JSON format:"
echo '  {"signal_mean": <value>, "noise_std": <value>, "snr": <value>}'
echo ""
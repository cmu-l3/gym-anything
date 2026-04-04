#!/bin/bash
echo "=== Setting up Analyze Histogram Peaks Task ==="

# Source utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Clean up any previous results
OUTPUT_FILE="/home/ga/Documents/SlicerData/histogram_analysis.json"
rm -f "$OUTPUT_FILE" 2>/dev/null || true
rm -f /tmp/histogram_task_result.json 2>/dev/null || true

# Ensure output directory exists
mkdir -p /home/ga/Documents/SlicerData
chown -R ga:ga /home/ga/Documents/SlicerData 2>/dev/null || true

# Verify sample data exists
SAMPLE_DATA="/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd"
if [ ! -f "$SAMPLE_DATA" ]; then
    echo "ERROR: Sample data not found at $SAMPLE_DATA"
    echo "Attempting to download..."
    mkdir -p /home/ga/Documents/SlicerData/SampleData
    
    # Try multiple download sources
    curl -L -o "$SAMPLE_DATA" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null || \
    wget -O "$SAMPLE_DATA" --timeout=120 \
        "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || true
    
    if [ ! -f "$SAMPLE_DATA" ] || [ $(stat -c%s "$SAMPLE_DATA" 2>/dev/null || echo 0) -lt 1000000 ]; then
        echo "WARNING: Could not download MRHead sample data"
    fi
    
    chown -R ga:ga /home/ga/Documents/SlicerData 2>/dev/null || true
fi

# Record initial state
if [ -f "$SAMPLE_DATA" ]; then
    SAMPLE_SIZE=$(stat -c%s "$SAMPLE_DATA" 2>/dev/null || echo "0")
    echo "Sample data found: $SAMPLE_DATA ($SAMPLE_SIZE bytes)"
    SAMPLE_EXISTS="true"
else
    echo "WARNING: Sample data not available"
    SAMPLE_EXISTS="false"
fi

# Kill any existing Slicer instances for clean start
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with empty scene
echo "Launching 3D Slicer..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Launch as ga user
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
WAIT_COUNT=0
MAX_WAIT=90
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    if pgrep -f "Slicer" > /dev/null 2>&1; then
        # Check for window
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
            echo "3D Slicer window detected"
            break
        fi
    fi
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 2))
done

if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
    echo "WARNING: Timeout waiting for Slicer window"
fi

# Additional wait for Slicer to fully load
sleep 10

# Maximize and focus Slicer window
SLICER_WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "slicer" | head -1 | awk '{print $1}')
if [ -n "$SLICER_WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$SLICER_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$SLICER_WID" 2>/dev/null || true
    echo "Slicer window maximized and focused"
fi

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

# Save initial state JSON
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "sample_data_exists": $SAMPLE_EXISTS,
    "sample_data_path": "$SAMPLE_DATA",
    "output_file_path": "$OUTPUT_FILE",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Analyze Volume Intensity Histogram"
echo ""
echo "Instructions:"
echo "1. Load MRHead.nrrd from ~/Documents/SlicerData/SampleData/"
echo "2. View the intensity histogram (Volumes module -> Volume Information)"
echo "3. Identify three peaks: background, low tissue, high tissue"
echo "4. Save results to ~/Documents/SlicerData/histogram_analysis.json"
echo ""
echo "Sample data: $SAMPLE_DATA"
echo "Output file: $OUTPUT_FILE"
echo ""
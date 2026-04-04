#!/bin/bash
echo "=== Setting up Threshold Brain Segmentation Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure output directory exists and is clean
OUTPUT_DIR="/home/ga/Documents/SlicerData/Exports"
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/brain_segmentation.seg.nrrd" 2>/dev/null || true
rm -f "$OUTPUT_DIR/brain_segmentation.nrrd" 2>/dev/null || true
rm -f "$OUTPUT_DIR/*.seg.nrrd" 2>/dev/null || true
chown -R ga:ga "$OUTPUT_DIR"

# Record initial state - no segmentation files should exist
INITIAL_SEG_COUNT=$(ls -1 "$OUTPUT_DIR"/*.seg.nrrd 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_SEG_COUNT" > /tmp/initial_seg_count.txt
echo "Initial segmentation count: $INITIAL_SEG_COUNT"

# Verify sample data exists
SAMPLE_DATA="/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd"
if [ ! -f "$SAMPLE_DATA" ]; then
    echo "Sample data not found, attempting to download..."
    mkdir -p "$(dirname "$SAMPLE_DATA")"
    
    # Try multiple download sources
    DOWNLOAD_SUCCESS=false
    
    # Source 1: Slicer testing data
    if curl -L -o "$SAMPLE_DATA" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null; then
        if [ -f "$SAMPLE_DATA" ] && [ $(stat -c%s "$SAMPLE_DATA" 2>/dev/null || echo 0) -gt 1000000 ]; then
            DOWNLOAD_SUCCESS=true
            echo "Downloaded MRHead from Slicer testing data"
        fi
    fi
    
    # Source 2: Kitware data
    if [ "$DOWNLOAD_SUCCESS" = "false" ]; then
        if wget --timeout=120 -O "$SAMPLE_DATA" \
            "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null; then
            if [ -f "$SAMPLE_DATA" ] && [ $(stat -c%s "$SAMPLE_DATA" 2>/dev/null || echo 0) -gt 1000000 ]; then
                DOWNLOAD_SUCCESS=true
                echo "Downloaded MRHead from Kitware"
            fi
        fi
    fi
    
    if [ "$DOWNLOAD_SUCCESS" = "false" ]; then
        echo "ERROR: Could not download sample data"
        exit 1
    fi
    
    chown ga:ga "$SAMPLE_DATA" 2>/dev/null || true
fi

# Verify sample data is valid
SAMPLE_SIZE=$(stat -c%s "$SAMPLE_DATA" 2>/dev/null || echo "0")
echo "Sample file size: $SAMPLE_SIZE bytes"

if [ "$SAMPLE_SIZE" -lt 1000000 ]; then
    echo "ERROR: Sample data file too small (possibly corrupt)"
    exit 1
fi

# Clear any previous task results
rm -f /tmp/seg_task_result.json 2>/dev/null || true
rm -f /tmp/segmentation_analysis.json 2>/dev/null || true

# Kill any existing Slicer instances for clean start
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the sample data pre-loaded
echo "Launching 3D Slicer with MRHead.nrrd..."
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$SAMPLE_DATA' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
for i in {1..60}; do
    if pgrep -f "Slicer" > /dev/null 2>&1; then
        WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Slicer\|3D Slicer\|MRHead" | head -1 | awk '{print $1}')
        if [ -n "$WID" ]; then
            echo "Slicer window detected after ${i}s"
            break
        fi
    fi
    sleep 1
done

# Wait additional time for data to fully load
echo "Waiting for data to load..."
sleep 10

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot showing loaded data
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Create a threshold-based brain tissue segmentation"
echo ""
echo "The MRHead brain MRI is loaded. You need to:"
echo "  1. Open Segment Editor module"
echo "  2. Add a new segment named 'BrainTissue'"
echo "  3. Use the Threshold effect to select brain tissue"
echo "  4. Apply the threshold and save the segmentation to:"
echo "     $OUTPUT_DIR/brain_segmentation.seg.nrrd"
echo ""
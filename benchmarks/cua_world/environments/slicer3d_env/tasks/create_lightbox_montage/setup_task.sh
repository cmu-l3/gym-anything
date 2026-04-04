#!/bin/bash
echo "=== Setting up Create Lightbox Montage task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create export directory
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"
mkdir -p "$EXPORT_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Remove any pre-existing montage file (ensures fresh creation)
OUTPUT_FILE="$EXPORT_DIR/brain_montage.png"
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing existing montage file..."
    rm -f "$OUTPUT_FILE"
fi

# Record initial state
echo "false" > /tmp/initial_montage_exists.txt
ls -la "$EXPORT_DIR" > /tmp/initial_exports_list.txt 2>/dev/null || true

# Verify MRHead sample data exists
SAMPLE_DATA="/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd"
if [ ! -f "$SAMPLE_DATA" ]; then
    echo "Sample data not found, attempting to download..."
    mkdir -p "$(dirname $SAMPLE_DATA)"
    
    # Try multiple download URLs
    curl -L -o "$SAMPLE_DATA" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null || \
    wget --timeout=120 -O "$SAMPLE_DATA" \
        "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || true
    
    chown ga:ga "$SAMPLE_DATA" 2>/dev/null || true
fi

if [ ! -f "$SAMPLE_DATA" ]; then
    echo "ERROR: Sample data not found at $SAMPLE_DATA"
    exit 1
fi

SAMPLE_SIZE=$(stat -c%s "$SAMPLE_DATA" 2>/dev/null || echo "0")
echo "Sample data: $SAMPLE_DATA ($SAMPLE_SIZE bytes)"

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with MRHead loaded
echo "Launching 3D Slicer with MRHead brain MRI..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer "$SAMPLE_DATA" > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
for i in {1..60}; do
    if pgrep -f "Slicer" > /dev/null 2>&1; then
        WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "slicer" | head -1 | awk '{print $1}')
        if [ -n "$WID" ]; then
            echo "3D Slicer window detected"
            break
        fi
    fi
    sleep 2
done

# Wait additional time for data to load
echo "Waiting for MRHead data to load..."
sleep 10

# Maximize window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    INIT_SIZE=$(stat -c%s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: $INIT_SIZE bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "MRHead brain MRI is loaded in 3D Slicer."
echo ""
echo "TASK: Create a 5x4 lightbox montage of axial brain slices"
echo ""
echo "Steps:"
echo "  1. Go to Modules → Utilities → Screen Capture"
echo "  2. Set Animation mode to 'lightbox'"
echo "  3. Configure: 5 columns, 4 rows, Red (axial) view"
echo "  4. Set output path: $OUTPUT_FILE"
echo "  5. Click Capture"
echo ""
echo "Output file must be saved to: $OUTPUT_FILE"
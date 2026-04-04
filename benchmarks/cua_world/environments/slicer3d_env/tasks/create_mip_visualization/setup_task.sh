#!/bin/bash
echo "=== Setting up Create MIP Visualization Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Set up directories
SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"
SAMPLE_FILE="$SAMPLE_DIR/CTChest.nrrd"
OUTPUT_FILE="$EXPORT_DIR/chest_mip_coronal.png"

mkdir -p "$SAMPLE_DIR"
mkdir -p "$EXPORT_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Clean any previous task outputs
rm -f "$OUTPUT_FILE" 2>/dev/null || true
rm -f /tmp/mip_task_result.json 2>/dev/null || true

# Record initial state - check if output already exists
if [ -f "$OUTPUT_FILE" ]; then
    INITIAL_OUTPUT_EXISTS="true"
    INITIAL_OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    INITIAL_OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
else
    INITIAL_OUTPUT_EXISTS="false"
    INITIAL_OUTPUT_MTIME="0"
    INITIAL_OUTPUT_SIZE="0"
fi

cat > /tmp/initial_state.json << EOF
{
    "output_exists": $INITIAL_OUTPUT_EXISTS,
    "output_mtime": $INITIAL_OUTPUT_MTIME,
    "output_size": $INITIAL_OUTPUT_SIZE,
    "task_start_time": $(date +%s),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Ensure CTChest.nrrd sample data exists
if [ ! -f "$SAMPLE_FILE" ] || [ "$(stat -c %s "$SAMPLE_FILE" 2>/dev/null || echo 0)" -lt 1000000 ]; then
    echo "Downloading CTChest sample data..."
    
    # Try primary URL
    if curl -L -o "$SAMPLE_FILE" --connect-timeout 30 --max-time 180 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/4507b664690840abb6cb9af2d919377ffc4ef75b167cb6fd0f747befdb12e38e" 2>/dev/null; then
        if [ -f "$SAMPLE_FILE" ] && [ "$(stat -c %s "$SAMPLE_FILE" 2>/dev/null || echo 0)" -gt 10000000 ]; then
            echo "CTChest.nrrd downloaded successfully"
        else
            echo "Download incomplete, trying alternative..."
            rm -f "$SAMPLE_FILE" 2>/dev/null || true
        fi
    fi
    
    # Try alternative URL if primary failed
    if [ ! -f "$SAMPLE_FILE" ] || [ "$(stat -c %s "$SAMPLE_FILE" 2>/dev/null || echo 0)" -lt 10000000 ]; then
        echo "Trying alternative download URL..."
        curl -L -o "$SAMPLE_FILE" --connect-timeout 30 --max-time 180 \
            "https://data.kitware.com/api/v1/file/5c4d2f3b8d777f072bf6cef7/download" 2>/dev/null || true
    fi
    
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

# Verify sample file exists and has reasonable size
if [ ! -f "$SAMPLE_FILE" ]; then
    echo "ERROR: CTChest.nrrd not found at $SAMPLE_FILE"
    echo "Task cannot proceed without sample data"
    exit 1
fi

SAMPLE_SIZE=$(stat -c %s "$SAMPLE_FILE" 2>/dev/null || echo "0")
echo "Sample file: $SAMPLE_FILE ($(du -h "$SAMPLE_FILE" 2>/dev/null | cut -f1))"

if [ "$SAMPLE_SIZE" -lt 10000000 ]; then
    echo "WARNING: Sample file seems small ($SAMPLE_SIZE bytes)"
fi

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with the chest CT data
echo "Launching 3D Slicer with CTChest data..."
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$SAMPLE_FILE' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
sleep 8

# Wait for Slicer window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer\|3D Slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 1
done

# Wait additional time for data to load
echo "Waiting for CT data to load..."
sleep 10

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot to verify setup
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    INIT_SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: $INIT_SIZE bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Create a Maximum Intensity Projection (MIP) visualization"
echo ""
echo "Data loaded: $SAMPLE_FILE"
echo "Expected output: $OUTPUT_FILE"
echo ""
echo "Instructions:"
echo "  1. Select the coronal (green) slice view"
echo "  2. Enable slab mode (click layers/slab icon in slice controller)"
echo "  3. Set slab type to 'Max' (MIP)"
echo "  4. Set slab thickness to at least 30mm"
echo "  5. Save screenshot to: $OUTPUT_FILE"
echo ""
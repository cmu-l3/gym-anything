#!/bin/bash
echo "=== Setting up Save Scene Bundle Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Define paths
SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_FILE="$EXPORTS_DIR/annotated_brain_scene.mrb"

# Ensure directories exist
mkdir -p "$SAMPLE_DIR"
mkdir -p "$EXPORTS_DIR"
chown -R ga:ga "/home/ga/Documents/SlicerData"

# Clean up any existing output file (ensure fresh task state)
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing existing output file..."
    rm -f "$OUTPUT_FILE"
fi

# Record initial state - no output file should exist
echo "false" > /tmp/initial_output_exists.txt

# Record list of existing files in exports dir
ls -la "$EXPORTS_DIR" 2>/dev/null > /tmp/initial_exports_list.txt || true

# Ensure sample data exists
if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Sample file not found, attempting to download..."
    
    # Try multiple sources
    DOWNLOADED=false
    
    # Source 1: Slicer testing data
    if ! $DOWNLOADED; then
        wget -q -O "$SAMPLE_FILE" \
            "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null
        if [ -f "$SAMPLE_FILE" ] && [ "$(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo 0)" -gt 1000000 ]; then
            DOWNLOADED=true
            echo "Downloaded from Slicer testing data"
        fi
    fi
    
    # Source 2: Kitware data
    if ! $DOWNLOADED; then
        wget -q -O "$SAMPLE_FILE" \
            "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null
        if [ -f "$SAMPLE_FILE" ] && [ "$(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo 0)" -gt 1000000 ]; then
            DOWNLOADED=true
            echo "Downloaded from Kitware"
        fi
    fi
    
    if ! $DOWNLOADED; then
        echo "ERROR: Could not download sample data"
        # Create synthetic fallback
        echo "Creating synthetic NRRD data as fallback..."
        python3 << 'PYEOF'
import numpy as np
import os

shape = (64, 64, 64)
data = np.zeros(shape, dtype=np.int16)
center = np.array(shape) / 2

for x in range(shape[0]):
    for y in range(shape[1]):
        for z in range(shape[2]):
            dist = np.sqrt((x - center[0])**2 + (y - center[1])**2 + (z - center[2])**2)
            if dist < 25:
                data[x, y, z] = 800 + int(200 * np.sin(dist / 3))
            elif dist < 28:
                data[x, y, z] = 1200

output_path = '/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd'
with open(output_path, 'wb') as f:
    header = """NRRD0004
type: int16
dimension: 3
space: left-posterior-superior
sizes: 64 64 64
space directions: (2,0,0) (0,2,0) (0,0,2)
kinds: domain domain domain
endian: little
encoding: raw
space origin: (-64,-64,-64)

"""
    f.write(header.encode('ascii'))
    f.write(data.tobytes())
print("Synthetic MRHead.nrrd created")
PYEOF
    fi
fi

# Verify sample file exists
if [ -f "$SAMPLE_FILE" ]; then
    SAMPLE_SIZE=$(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo "0")
    echo "Sample file ready: $SAMPLE_FILE ($SAMPLE_SIZE bytes)"
else
    echo "ERROR: Sample file not available"
fi

# Set permissions
chown -R ga:ga "$SAMPLE_DIR" 2>/dev/null || true
chown -R ga:ga "$EXPORTS_DIR" 2>/dev/null || true
chmod -R 755 "/home/ga/Documents/SlicerData" 2>/dev/null || true

# Kill any existing Slicer instances for clean start
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with empty scene
echo "Launching 3D Slicer..."
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --no-splash > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
for i in {1..60}; do
    if pgrep -f "Slicer" > /dev/null 2>&1; then
        WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Slicer\|3D Slicer" | head -1 | awk '{print $1}')
        if [ -n "$WID" ]; then
            echo "3D Slicer window detected"
            break
        fi
    fi
    sleep 1
done

# Wait for Slicer to fully load
echo "Waiting for 3D Slicer to fully load..."
sleep 10

# Maximize and focus window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Slicer" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    echo "Slicer window maximized and focused"
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Save a scene bundle with annotated fiducials"
echo ""
echo "Instructions:"
echo "  1. Load MRHead.nrrd from: $SAMPLE_FILE"
echo "  2. Place a fiducial marker and name it 'Landmark_A'"
echo "  3. Place another fiducial at a DIFFERENT location and name it 'Landmark_B'"
echo "  4. Save the scene as MRB to: $OUTPUT_FILE"
echo ""
echo "Sample data location: $SAMPLE_FILE"
echo "Output file should be: $OUTPUT_FILE"
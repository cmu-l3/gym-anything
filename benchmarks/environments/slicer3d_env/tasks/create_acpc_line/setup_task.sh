#!/bin/bash
echo "=== Setting up AC-PC Line Creation Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Directories
SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_FILE="$EXPORT_DIR/ACPC_landmarks.mrk.json"

# Ensure directories exist
mkdir -p "$SAMPLE_DIR"
mkdir -p "$EXPORT_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Record initial state
echo "Recording initial state..."
if [ -f "$OUTPUT_FILE" ]; then
    INITIAL_OUTPUT_EXISTS="true"
    INITIAL_OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
else
    INITIAL_OUTPUT_EXISTS="false"
    INITIAL_OUTPUT_MTIME="0"
fi

cat > /tmp/acpc_initial_state.json << EOF
{
    "output_existed": $INITIAL_OUTPUT_EXISTS,
    "output_mtime": $INITIAL_OUTPUT_MTIME,
    "task_start_time": $(date +%s),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/acpc_initial_state.json

# Clean previous output to ensure fresh work
rm -f "$OUTPUT_FILE" 2>/dev/null || true
rm -f /tmp/acpc_task_result.json 2>/dev/null || true

# Ensure sample data exists (MRHead.nrrd)
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"
if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Downloading MRHead sample data..."
    # Try primary URL
    curl -L -o "$SAMPLE_FILE" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null
    
    # Verify download
    if [ ! -f "$SAMPLE_FILE" ] || [ $(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo 0) -lt 1000000 ]; then
        echo "Primary download failed, trying alternative..."
        wget --timeout=120 -O "$SAMPLE_FILE" \
            "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || true
    fi
    
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

# Verify sample file
if [ -f "$SAMPLE_FILE" ]; then
    FILE_SIZE=$(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo 0)
    echo "Sample file: $SAMPLE_FILE ($FILE_SIZE bytes)"
else
    echo "WARNING: Sample file not found at $SAMPLE_FILE"
fi

# Compute reference AC-PC coordinates for this specific volume
# These are approximate anatomical locations for MRHead
echo "Computing reference coordinates..."
python3 << 'PYEOF'
import os
import json

# Reference coordinates for MRHead (determined by neuroanatomical analysis)
# These are in RAS coordinates
reference = {
    "ac_ras": [-0.5, 2.0, -4.0],
    "pc_ras": [-0.5, -23.0, -2.0],
    "expected_distance_mm": 25.0,
    "distance_range": {"min": 20.0, "max": 32.0},
    "notes": "Reference AC-PC coordinates for MRHead sample"
}

# Save for verification
with open("/tmp/acpc_reference.json", "w") as f:
    json.dump(reference, f, indent=2)

print("Reference coordinates saved")
print(f"  AC (RAS): {reference['ac_ras']}")
print(f"  PC (RAS): {reference['pc_ras']}")
print(f"  Expected distance: {reference['expected_distance_mm']} mm")
PYEOF

# Launch 3D Slicer with the sample data
echo "Launching 3D Slicer with MRHead data..."

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the sample file
if [ -f "$SAMPLE_FILE" ]; then
    su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$SAMPLE_FILE' > /tmp/slicer_acpc.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer > /tmp/slicer_acpc.log 2>&1 &"
fi

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
sleep 8

# Wait for window
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait for data to load
echo "Waiting for data to load..."
sleep 5

# Maximize and focus
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/acpc_initial.png 2>/dev/null || true

# Verify screenshot
if [ -f /tmp/acpc_initial.png ]; then
    SIZE=$(stat -c%s /tmp/acpc_initial.png 2>/dev/null || echo 0)
    echo "Initial screenshot captured: $SIZE bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Create AC-PC Line for Stereotactic Planning"
echo ""
echo "Instructions:"
echo "  1. Navigate to the midsagittal plane (sagittal view)"
echo "  2. Identify the Anterior Commissure (AC) - small white matter bundle"
echo "     crossing the midline, anterior to fornix columns"
echo "  3. Place a fiducial labeled 'AC' at the anterior border of AC"
echo "  4. Identify the Posterior Commissure (PC) - at junction of"
echo "     cerebral aqueduct and third ventricle"
echo "  5. Place a fiducial labeled 'PC' at this location"
echo "  6. Create a line connecting AC and PC"
echo "  7. Verify distance is ~23-28mm"
echo "  8. Save markups to: $OUTPUT_FILE"
echo ""
echo "Sample data: $SAMPLE_FILE"
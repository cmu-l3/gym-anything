#!/bin/bash
echo "=== Setting up Define Oblique Plane Task ==="

source /workspace/scripts/task_utils.sh

SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"
OUTPUT_DIR="/home/ga/Documents/SlicerData"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(date -Iseconds)"

# Clean any previous task results
rm -f /tmp/plane_task_result.json 2>/dev/null || true
rm -f "$OUTPUT_DIR/acpc_plane.mrk.json" 2>/dev/null || true

# Ensure sample data exists
if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Sample file not found, attempting to download..."
    mkdir -p "$SAMPLE_DIR"
    
    # Try multiple download sources
    wget -q -O "$SAMPLE_FILE" \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null || \
    curl -L -o "$SAMPLE_FILE" \
        "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || \
        echo "WARNING: Could not download MRHead sample data"
    
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

# Verify sample file
if [ -f "$SAMPLE_FILE" ]; then
    SAMPLE_SIZE=$(stat -c %s "$SAMPLE_FILE" 2>/dev/null || echo "0")
    echo "Sample file: $SAMPLE_FILE ($SAMPLE_SIZE bytes)"
    if [ "$SAMPLE_SIZE" -lt 1000000 ]; then
        echo "WARNING: Sample file seems too small"
    fi
else
    echo "ERROR: Sample file not available at $SAMPLE_FILE"
fi

# Create ground truth reference for AC-PC landmarks
# These are approximate coordinates for MRHead dataset
mkdir -p "$GROUND_TRUTH_DIR"
chmod 700 "$GROUND_TRUTH_DIR"

cat > "$GROUND_TRUTH_DIR/acpc_landmarks.json" << 'GTEOF'
{
    "description": "Reference AC-PC landmarks for MRHead dataset",
    "dataset": "MRHead.nrrd",
    "coordinate_system": "RAS",
    "landmarks": {
        "anterior_commissure": {
            "name": "AC",
            "ras": [0.0, 1.5, -4.0],
            "tolerance_mm": 5.0,
            "description": "Center of anterior commissure on midsagittal plane"
        },
        "posterior_commissure": {
            "name": "PC",
            "ras": [0.0, -24.5, -2.0],
            "tolerance_mm": 5.0,
            "description": "Center of posterior commissure at aqueduct junction"
        },
        "superior_midline": {
            "name": "Superior Midline Point",
            "ras_range": {
                "R": [-5, 5],
                "A": [-50, 50],
                "S": [10, 100]
            },
            "description": "Any point on midline superior to AC-PC line"
        }
    },
    "expected_ac_pc_distance_mm": 26.0,
    "expected_plane_normal": [0.0, -0.08, 0.997],
    "plane_normal_tolerance_deg": 30.0
}
GTEOF

chmod 644 "$GROUND_TRUTH_DIR/acpc_landmarks.json"
echo "Ground truth landmarks created"

# Ensure output directory exists and is writable
mkdir -p "$OUTPUT_DIR"
chown -R ga:ga "$OUTPUT_DIR" 2>/dev/null || true
chmod 755 "$OUTPUT_DIR"

# Record initial markup count (for detecting new markups)
echo "0" > /tmp/initial_plane_count.txt

# Launch 3D Slicer with sample data
echo "Launching 3D Slicer with brain MRI..."

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Start Slicer with the MRI data
if [ -f "$SAMPLE_FILE" ]; then
    su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$SAMPLE_FILE' > /tmp/slicer_launch.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer > /tmp/slicer_launch.log 2>&1 &"
fi

# Wait for Slicer to start
echo "Waiting for 3D Slicer to load..."
sleep 8

# Wait for window to appear
for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Additional wait for data to load
sleep 5

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial screenshot..."
take_screenshot /tmp/task_initial.png ga
sleep 1

# Verify screenshot captured
if [ -f /tmp/task_initial.png ]; then
    INIT_SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: $INIT_SIZE bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Define AC-PC Plane Through Anatomical Landmarks"
echo ""
echo "Instructions:"
echo "1. Create a Plane markup in the Markups module"
echo "2. Place control points at:"
echo "   - Anterior Commissure (AC) - midsagittal, anterior to fornix"
echo "   - Posterior Commissure (PC) - midsagittal, below pineal"
echo "   - Superior midline point - on falx, above AC-PC line"
echo "3. Save plane to: $OUTPUT_DIR/acpc_plane.mrk.json"
echo ""
echo "The MRHead brain MRI is loaded. Use sagittal view for best visualization."
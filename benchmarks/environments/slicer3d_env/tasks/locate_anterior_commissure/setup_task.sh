#!/bin/bash
echo "=== Setting up Locate Anterior Commissure Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
DATA_FILE="$SAMPLE_DIR/MRHead.nrrd"

# Create directories
mkdir -p "$GROUND_TRUTH_DIR"
chmod 700 "$GROUND_TRUTH_DIR"

# Verify sample data exists
if [ ! -f "$DATA_FILE" ]; then
    echo "Sample data not found, attempting to download..."
    mkdir -p "$SAMPLE_DIR"
    
    # Try primary URL
    curl -L -o "$DATA_FILE" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null
    
    # Verify download
    if [ ! -f "$DATA_FILE" ] || [ $(stat -c%s "$DATA_FILE" 2>/dev/null || echo 0) -lt 1000000 ]; then
        echo "Primary download failed, trying alternative..."
        wget -O "$DATA_FILE" --timeout=120 \
            "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || true
    fi
    
    chown ga:ga "$DATA_FILE" 2>/dev/null || true
fi

# Verify data file exists and is valid
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: MRHead.nrrd not found and could not be downloaded"
    exit 1
fi

FILE_SIZE=$(stat -c%s "$DATA_FILE" 2>/dev/null || echo 0)
echo "MRHead.nrrd size: $FILE_SIZE bytes"

if [ "$FILE_SIZE" -lt 1000000 ]; then
    echo "ERROR: MRHead.nrrd appears to be incomplete or corrupted"
    exit 1
fi

# Create ground truth landmarks file
# AC coordinates for MRHead determined by neuroanatomical reference
cat > "$GROUND_TRUTH_DIR/mrhead_landmarks.json" << 'GTEOF'
{
  "volume": "MRHead.nrrd",
  "landmarks": {
    "anterior_commissure": {
      "name": "Anterior Commissure (AC)",
      "coordinates_ras": [0.0, 1.5, -3.0],
      "tolerance_mm": 5.0,
      "precision_tolerance_mm": 3.0,
      "description": "Center of anterior commissure at midline crossing"
    },
    "posterior_commissure": {
      "name": "Posterior Commissure (PC)",
      "coordinates_ras": [0.0, -24.0, -2.0],
      "tolerance_mm": 5.0,
      "description": "Reference landmark for AC-PC plane"
    }
  },
  "coordinate_system": "RAS",
  "notes": "Coordinates based on standard neuroimaging atlas reference for MRHead sample"
}
GTEOF
chmod 600 "$GROUND_TRUTH_DIR/mrhead_landmarks.json"

# Record initial fiducial count (should be 0)
echo "0" > /tmp/initial_fiducial_count.txt

# Clear any previous task results
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/ac_fiducial_data.json 2>/dev/null || true

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with MRHead data pre-loaded
echo "Launching 3D Slicer with MRHead data..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer "$DATA_FILE" > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
echo "Waiting for 3D Slicer to start and load data..."
wait_for_slicer 90

# Additional wait for data to fully load
sleep 5

# Maximize and focus window
SLICER_WID=$(get_slicer_window_id)
if [ -n "$SLICER_WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$SLICER_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$SLICER_WID" 2>/dev/null || true
    echo "Slicer window focused and maximized"
fi

# Dismiss any startup dialogs
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png ga

# Verify initial state
if [ -f /tmp/task_initial_state.png ]; then
    INIT_SIZE=$(stat -c%s /tmp/task_initial_state.png 2>/dev/null || echo 0)
    echo "Initial screenshot captured: $INIT_SIZE bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo "Data loaded: $DATA_FILE"
echo ""
echo "TASK: Locate the anterior commissure (AC) in the brain MRI and place a fiducial marker at its center."
echo ""
echo "The AC is a small white matter bundle crossing the midline, located deep in the brain."
echo "It should be visible in the midsagittal plane as a bright structure."
echo ""
echo "Place your fiducial within 5mm of the true AC location to pass."
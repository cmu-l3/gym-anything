#!/bin/bash
echo "=== Setting up Export DICOM Series task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Define paths
SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports/DICOM_Export"

# Ensure sample data exists
echo "Checking sample data..."
if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Sample file not found. Downloading MRHead..."
    mkdir -p "$SAMPLE_DIR"
    
    # Try primary URL
    curl -L -o "$SAMPLE_FILE" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null
    
    # Try alternative if failed
    if [ ! -f "$SAMPLE_FILE" ] || [ $(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo 0) -lt 1000000 ]; then
        echo "Trying alternative download URL..."
        wget -O "$SAMPLE_FILE" --timeout=120 \
            "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || true
    fi
    
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

# Verify sample file
if [ -f "$SAMPLE_FILE" ]; then
    SAMPLE_SIZE=$(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo "0")
    echo "Sample file found: $SAMPLE_FILE ($SAMPLE_SIZE bytes)"
else
    echo "ERROR: Could not obtain sample data file"
    exit 1
fi

# Create and clean export directory
echo "Preparing export directory..."
mkdir -p "$EXPORT_DIR"
rm -rf "$EXPORT_DIR"/* 2>/dev/null || true
chown -R ga:ga "/home/ga/Documents/SlicerData/Exports" 2>/dev/null || true
chmod -R 755 "/home/ga/Documents/SlicerData/Exports" 2>/dev/null || true

# Record initial state - export directory should be empty
INITIAL_FILE_COUNT=$(find "$EXPORT_DIR" -type f 2>/dev/null | wc -l)
echo "$INITIAL_FILE_COUNT" > /tmp/initial_dicom_count.txt
echo "Initial DICOM file count: $INITIAL_FILE_COUNT"

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with the sample file loaded
echo "Launching 3D Slicer with MRHead sample..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$SAMPLE_FILE' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
for i in $(seq 1 60); do
    if pgrep -f "Slicer" > /dev/null 2>&1; then
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
            echo "3D Slicer window detected"
            break
        fi
    fi
    sleep 2
done

# Additional wait for Slicer to fully load the data
echo "Waiting for data to load..."
sleep 10

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Verify Slicer is running and data is loaded
SLICER_RUNNING=$(pgrep -f "Slicer" > /dev/null && echo "true" || echo "false")
echo "Slicer running: $SLICER_RUNNING"

# Take initial screenshot
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    INIT_SCREENSHOT_SIZE=$(stat -c%s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: $INIT_SCREENSHOT_SIZE bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Save setup state
cat > /tmp/setup_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "sample_file_exists": $([ -f "$SAMPLE_FILE" ] && echo "true" || echo "false"),
    "sample_file_size": $(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo "0"),
    "export_dir_exists": $([ -d "$EXPORT_DIR" ] && echo "true" || echo "false"),
    "initial_dicom_count": $INITIAL_FILE_COUNT,
    "slicer_running": $SLICER_RUNNING,
    "export_directory": "$EXPORT_DIR"
}
EOF

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK INSTRUCTIONS:"
echo "=================="
echo "The MRHead brain MRI is loaded in 3D Slicer."
echo ""
echo "1. Go to Modules → Informatics → DICOM"
echo "2. Click the 'Export' tab"
echo "3. Select MRHead volume"
echo "4. Set Patient Name: SlicerExportTest"
echo "5. Set Study Description: Brain MRI Export Task"
echo "6. Set Output Directory: $EXPORT_DIR"
echo "7. Click Export"
echo ""
echo "Expected output: ~130 DICOM files in the export directory"
echo ""
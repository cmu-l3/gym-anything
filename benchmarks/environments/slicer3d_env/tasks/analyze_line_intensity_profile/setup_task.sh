#!/bin/bash
echo "=== Setting up Analyze Line Intensity Profile Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Define paths
SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"
OUTPUT_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_CSV="$OUTPUT_DIR/line_profile_output.csv"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown -R ga:ga "$OUTPUT_DIR" 2>/dev/null || true
chmod 755 "$OUTPUT_DIR"

# Clean previous task results
rm -f /tmp/line_profile_result.json 2>/dev/null || true
rm -f "$OUTPUT_CSV" 2>/dev/null || true
rm -f /tmp/task_initial.png 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# Record initial state - no output file should exist
echo "0" > /tmp/initial_csv_exists.txt
if [ -f "$OUTPUT_CSV" ]; then
    echo "WARNING: Output CSV already exists, removing..."
    rm -f "$OUTPUT_CSV"
fi

# Count initial markup files
INITIAL_MARKUP_COUNT=$(find /home/ga/Documents/SlicerData -name "*.mrk.json" 2>/dev/null | wc -l)
echo "$INITIAL_MARKUP_COUNT" > /tmp/initial_markup_count.txt

# Verify sample data exists
if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Sample file not found at $SAMPLE_FILE"
    echo "Attempting to download MRHead..."
    mkdir -p "$SAMPLE_DIR"
    
    # Try primary URL
    curl -L -o "$SAMPLE_FILE" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null
    
    if [ ! -f "$SAMPLE_FILE" ] || [ $(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo 0) -lt 1000000 ]; then
        echo "Primary download failed, trying alternative..."
        wget --timeout=120 -O "$SAMPLE_FILE" \
            "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || true
    fi
    
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

# Verify sample file
if [ -f "$SAMPLE_FILE" ]; then
    FILE_SIZE=$(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo "0")
    echo "Sample file found: $SAMPLE_FILE ($FILE_SIZE bytes)"
else
    echo "ERROR: Could not obtain sample data"
    exit 1
fi

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with the sample data loaded
echo "Launching 3D Slicer with MRHead loaded..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Start Slicer with the sample file
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$SAMPLE_FILE' > /tmp/slicer_launch.log 2>&1 &"

echo "Waiting for 3D Slicer to start and load data..."

# Wait for Slicer window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer\|3D Slicer"; then
        echo "3D Slicer window detected (attempt $i)"
        break
    fi
    sleep 2
done

# Wait additional time for data to fully load
sleep 10

# Check if data is loaded
echo "Verifying data load..."
for i in {1..20}; do
    WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "")
    if echo "$WINDOW_TITLE" | grep -qi "MRHead\|Slicer"; then
        echo "Window title: $WINDOW_TITLE"
        break
    fi
    sleep 1
done

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SCREENSHOT_SIZE=$(stat -c%s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: $SCREENSHOT_SIZE bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Save setup info
cat > /tmp/setup_info.json << EOF
{
    "sample_file": "$SAMPLE_FILE",
    "output_csv_path": "$OUTPUT_CSV",
    "output_dir": "$OUTPUT_DIR",
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_markup_count": $INITIAL_MARKUP_COUNT,
    "setup_timestamp": "$(date -Iseconds)"
}
EOF

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Analyze Line Intensity Profile"
echo "--------------------------------------"
echo "Data: MRHead brain MRI is loaded"
echo ""
echo "Instructions:"
echo "1. Use the Markups module to create a Line (ruler)"
echo "2. Place line from frontal (anterior) to occipital (posterior) brain"
echo "3. Go to Modules → Quantification → Line Profile"
echo "4. Select your line and MRHead volume"
echo "5. Click 'Compute intensity profile'"
echo "6. Save the profile to: $OUTPUT_CSV"
echo ""
echo "The line should span 100-180mm through brain tissue."
echo "=== Ready for agent ==="
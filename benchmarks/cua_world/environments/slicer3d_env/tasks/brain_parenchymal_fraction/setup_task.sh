#!/bin/bash
echo "=== Setting up Brain Parenchymal Fraction Task ==="

source /workspace/scripts/task_utils.sh

# Output directory
OUTPUT_DIR="/home/ga/Documents/SlicerData/BrainAssessment"
SAMPLE_DATA="/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd"

# -------------------------------------------------------
# 1. Delete stale outputs BEFORE recording timestamp
# -------------------------------------------------------
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/brain_bpf.seg.nrrd" 2>/dev/null || true
rm -f "$OUTPUT_DIR/bpf_report.json" 2>/dev/null || true
rm -f "$OUTPUT_DIR/brain_3d.png" 2>/dev/null || true
rm -f "$OUTPUT_DIR"/*.seg.nrrd 2>/dev/null || true
rm -f "$OUTPUT_DIR"/*.json 2>/dev/null || true
rm -f "$OUTPUT_DIR"/*.png 2>/dev/null || true
chown -R ga:ga "$OUTPUT_DIR"

# Clear previous task results
rm -f /tmp/bpf_task_result.json 2>/dev/null || true
rm -f /tmp/bpf_analysis.json 2>/dev/null || true
rm -f /tmp/task_final_state.png 2>/dev/null || true

# -------------------------------------------------------
# 2. Record task start time (for anti-gaming checks)
# -------------------------------------------------------
date +%s > /tmp/task_start_time.txt
date -Iseconds > /tmp/task_start_timestamp.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# -------------------------------------------------------
# 3. Verify MRHead sample data exists and is valid
# -------------------------------------------------------
MRHEAD_URL="https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286affadf823a7e58df93"
MRHEAD_MIN_SIZE=1000000

download_mrhead() {
    local target="$1"
    mkdir -p "$(dirname "$target")"

    echo "Downloading MRHead from SlicerTestingData..."
    if curl -L -o "$target" --connect-timeout 30 --max-time 180 "$MRHEAD_URL" 2>/dev/null; then
        local sz=$(stat -c%s "$target" 2>/dev/null || echo 0)
        if [ "$sz" -gt "$MRHEAD_MIN_SIZE" ]; then
            echo "Downloaded MRHead.nrrd successfully ($sz bytes)"
            chown ga:ga "$target" 2>/dev/null || true
            return 0
        fi
        echo "Download too small ($sz bytes), removing"
        rm -f "$target"
    fi
    return 1
}

# Check if existing file is valid (not synthetic fallback)
NEED_DOWNLOAD=false
if [ ! -f "$SAMPLE_DATA" ]; then
    NEED_DOWNLOAD=true
else
    EXISTING_SIZE=$(stat -c%s "$SAMPLE_DATA" 2>/dev/null || echo 0)
    if [ "$EXISTING_SIZE" -lt "$MRHEAD_MIN_SIZE" ]; then
        echo "Existing MRHead too small ($EXISTING_SIZE bytes), re-downloading..."
        rm -f "$SAMPLE_DATA"
        NEED_DOWNLOAD=true
    fi
fi

if [ "$NEED_DOWNLOAD" = "true" ]; then
    if ! download_mrhead "$SAMPLE_DATA"; then
        echo "ERROR: Could not download MRHead sample data"
        exit 1
    fi
fi

SAMPLE_SIZE=$(stat -c%s "$SAMPLE_DATA" 2>/dev/null || echo "0")
echo "MRHead file size: $SAMPLE_SIZE bytes"

# -------------------------------------------------------
# 3b. Ensure Python dependencies for export analysis
# -------------------------------------------------------
# Fix corrupted typing_extensions (0-byte stub left by some base images)
TYPING_EXT="/usr/local/lib/python3.10/dist-packages/typing_extensions.py"
if [ -f "$TYPING_EXT" ] && [ "$(stat -c%s "$TYPING_EXT" 2>/dev/null)" -lt 100 ]; then
    rm -f "$TYPING_EXT" 2>/dev/null || true
    pip3 install -q --force-reinstall typing_extensions 2>/dev/null || true
fi
pip3 install -q pynrrd 2>/dev/null || true

# -------------------------------------------------------
# 4. Kill existing Slicer and launch with MRHead
# -------------------------------------------------------
pkill -f "Slicer" 2>/dev/null || true
sleep 2

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

# Wait for data to fully load
echo "Waiting for data to load..."
sleep 10

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true
if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "MRHead brain MRI is loaded in 3D Slicer."
echo "Output directory: $OUTPUT_DIR"
echo ""

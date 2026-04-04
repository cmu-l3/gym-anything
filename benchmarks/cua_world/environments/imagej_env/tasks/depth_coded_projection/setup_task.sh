#!/bin/bash
# Setup script for depth_coded_projection task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Setting up Depth-Coded Projection Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"
GT_DIR="/var/lib/imagej/ground_truth"

mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR"

# Ensure Ground Truth directory exists and is hidden/protected
mkdir -p "$GT_DIR"
chmod 755 "$GT_DIR"

# Clear previous results
rm -f "$RESULTS_DIR/depth_coded_fly_brain.png" 2>/dev/null || true
rm -f /tmp/depth_coded_result.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# ============================================================
# Generate Ground Truth MIP (Reference Structure)
# ============================================================
# We generate a standard grayscale Max Intensity Projection of the Fly Brain
# to use as a structural reference. The agent's output must match this structure
# but be colorized by depth.
GT_MIP_PATH="$GT_DIR/fly_brain_mip.tif"

if [ ! -f "$GT_MIP_PATH" ]; then
    echo "Generating Ground Truth Reference..."
    
    GT_MACRO="/tmp/generate_gt.ijm"
    cat > "$GT_MACRO" << 'MACROEOF'
run("Fly Brain");
run("Z Project...", "projection=[Max Intensity]");
saveAs("Tiff", "/var/lib/imagej/ground_truth/fly_brain_mip.tif");
close();
close();
eval("script", "System.exit(0);");
MACROEOF

    # Run headless if possible, or just run and kill
    FIJI_PATH=$(find_fiji_executable)
    if [ -n "$FIJI_PATH" ]; then
        "$FIJI_PATH" --headless -macro "$GT_MACRO" > /dev/null 2>&1 || \
        # Fallback if headless fails (some Fiji versions issue)
        (DISPLAY=:1 "$FIJI_PATH" -macro "$GT_MACRO" & PID=$!; sleep 10; kill $PID 2>/dev/null)
    fi
    
    if [ -f "$GT_MIP_PATH" ]; then
        echo "Ground Truth generated successfully."
    else
        echo "WARNING: Failed to generate Ground Truth."
    fi
fi

# ============================================================
# Prepare Fiji for the user
# ============================================================
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

# Launch Fiji
launch_fiji
sleep 5
wait_for_fiji 60

# Maximize window
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
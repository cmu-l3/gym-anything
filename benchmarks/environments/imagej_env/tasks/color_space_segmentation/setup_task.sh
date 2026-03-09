#!/bin/bash
# Setup script for Color Space Segmentation task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Color Space Segmentation Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"
HIDDEN_DIR="/home/ga/.hidden"

mkdir -p "$RESULTS_DIR"
mkdir -p "$HIDDEN_DIR"
chown -R ga:ga "$DATA_DIR"
chown -R ga:ga "$HIDDEN_DIR"

# Clear previous results
rm -f "$RESULTS_DIR/green_pepper_mask.png" 2>/dev/null || true
rm -f "/tmp/task_result.json" 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/task_start_time

# ============================================================
# Prepare Reference Image (Ground Truth Source)
# ============================================================
# We need to save the specific version of "Peppers" this Fiji uses
# so the verifier can generate an accurate ground truth mask.

echo "Preparing reference image..."
# Create a macro to open Peppers and save it as PNG for the verifier
REF_MACRO="/tmp/save_ref.ijm"
cat > "$REF_MACRO" << 'MACROEOF'
run("Peppers (178K)");
saveAs("PNG", "/home/ga/.hidden/peppers_reference.png");
close();
MACROEOF

# Run Fiji briefly to generate reference
FIJI_PATH=$(find_fiji_executable)
if [ -n "$FIJI_PATH" ]; then
    # Run headless or quick GUI mode
    xvfb-run -a "$FIJI_PATH" -macro "$REF_MACRO" > /dev/null 2>&1
    echo "Reference image saved to $HIDDEN_DIR/peppers_reference.png"
else
    echo "ERROR: Fiji not found"
    exit 1
fi

# Ensure permissions
chown ga:ga "$HIDDEN_DIR/peppers_reference.png"

# ============================================================
# Launch Fiji for the Agent
# ============================================================
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Launch Fiji
echo "Launching Fiji..."
su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &

# Wait for window
wait_for_fiji 60

# Maximize and focus
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
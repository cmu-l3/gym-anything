#!/bin/bash
# Setup script for science_payload_capacity_sweep task

echo "=== Setting up science_payload_capacity_sweep task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="$ROCKETS_DIR/ProjetoJupiter_Valetudo_2019.ork"

# Just to be safe, if it's missing, download it again
if [ ! -f "$TASK_ORK" ]; then
    echo "Downloading Valetudo rocket..."
    wget -q "https://raw.githubusercontent.com/RocketPy-Team/RocketSerializer/master/examples/ProjetoJupiter--Valetudo--2019/rocket.ork" -O "$TASK_ORK"
    chown ga:ga "$TASK_ORK"
fi

mkdir -p "$EXPORTS_DIR"
chown -R ga:ga "$EXPORTS_DIR"

# Clean up previous outputs to ensure clean state
rm -f "$EXPORTS_DIR/payload_curve.csv" 2>/dev/null || true
rm -f "$EXPORTS_DIR/payload_summary.txt" 2>/dev/null || true
rm -f "$ROCKETS_DIR/valetudo_payload_4kg.ork" 2>/dev/null || true

# Record ground truth and timestamp
echo "task_start_ts=$(date +%s)" > /tmp/payload_sweep_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the base rocket
launch_openrocket "$TASK_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot for evidence verification
take_screenshot /tmp/payload_sweep_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== science_payload_capacity_sweep task setup complete ==="
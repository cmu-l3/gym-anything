#!/bin/bash
# Setup script for avbay_mass_distribution_reconstruction task

echo "=== Setting up avbay_mass_distribution_reconstruction task ==="

# Source utilities
source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="$ROCKETS_DIR/avbay_base.ork"
SOURCE_ORK="/workspace/data/rockets/dual_parachute_deployment.ork"

# Create required directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to the working file
if [ -f "$SOURCE_ORK" ]; then
    cp "$SOURCE_ORK" "$TASK_ORK"
else
    # Fallback to the downloaded examples if workspace mounted data is missing
    cp "/home/ga/Documents/rockets/dual_parachute_deployment.ork" "$TASK_ORK" || { echo "FATAL: Could not find source .ork"; exit 1; }
fi
chown ga:ga "$TASK_ORK"

# Remove any previous output artifacts to ensure a clean state
rm -f "$ROCKETS_DIR/detailed_avbay_rocket.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/avbay_report.txt" 2>/dev/null || true

# Record ground truth and timestamps for anti-gaming verification
echo "task_start_ts=$(date +%s)" > /tmp/avbay_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the baseline rocket
launch_openrocket "$TASK_ORK"
sleep 3

# Wait for UI and focus
wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take an initial screenshot to document the starting state
take_screenshot /tmp/avbay_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== avbay_mass_distribution_reconstruction task setup complete ==="
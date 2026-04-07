#!/bin/bash
# Setup script for ttw_fin_structural_upgrade task

echo "=== Setting up ttw_fin_structural_upgrade task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="/workspace/data/rockets/dual_parachute_deployment.ork"
BASE_ORK="$ROCKETS_DIR/dual_parachute_deployment.ork"
TARGET_ORK="$ROCKETS_DIR/ttw_fin_upgrade.ork"
REPORT_FILE="$EXPORTS_DIR/ttw_upgrade_report.txt"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to base working file if needed
if [ ! -f "$BASE_ORK" ]; then
    cp "$SOURCE_ORK" "$BASE_ORK" 2>/dev/null || wget -q "https://raw.githubusercontent.com/openrocket/openrocket/master/core/src/main/resources/datafiles/examples/Dual%20parachute%20deployment.ork" -O "$BASE_ORK"
fi
chown ga:ga "$BASE_ORK"

# Remove previous output files
rm -f "$TARGET_ORK" 2>/dev/null || true
rm -f "$REPORT_FILE" 2>/dev/null || true

# Record ground truth and timestamp
echo "task_start_ts=$(date +%s)" > /tmp/ttw_upgrade_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the base rocket
launch_openrocket "$BASE_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/ttw_upgrade_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== ttw_fin_structural_upgrade task setup complete ==="
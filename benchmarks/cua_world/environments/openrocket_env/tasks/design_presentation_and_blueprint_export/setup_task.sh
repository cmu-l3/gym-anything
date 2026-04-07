#!/bin/bash
# Setup script for design_presentation_and_blueprint_export task

echo "=== Setting up design_presentation_and_blueprint_export task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="/workspace/data/rockets/simple_model_rocket.ork"
WORK_ORK="$ROCKETS_DIR/simple_model_rocket.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to workspace to ensure a clean starting point
cp "$SOURCE_ORK" "$WORK_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$WORK_ORK"

# Remove any previous outputs
rm -f "$ROCKETS_DIR/cdr_rocket.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/design_report.pdf" 2>/dev/null || true
rm -f "$EXPORTS_DIR/fin_alignment_guide.pdf" 2>/dev/null || true

# Record ground truth timestamp for anti-gaming checks
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/cdr_task_start.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the baseline simple rocket
launch_openrocket "$WORK_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot to document starting state
take_screenshot /tmp/cdr_task_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== design_presentation_and_blueprint_export task setup complete ==="
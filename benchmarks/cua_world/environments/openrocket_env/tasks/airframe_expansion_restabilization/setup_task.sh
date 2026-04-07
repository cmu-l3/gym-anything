#!/bin/bash
echo "=== Setting up airframe_expansion_restabilization task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy base rocket
cp "/workspace/data/rockets/simple_model_rocket.ork" "$ROCKETS_DIR/simple_model_rocket.ork" 2>/dev/null || \
  wget -q "https://raw.githubusercontent.com/openrocket/openrocket/master/core/src/main/resources/datafiles/examples/A%20simple%20model%20rocket.ork" -O "$ROCKETS_DIR/simple_model_rocket.ork"
chown ga:ga "$ROCKETS_DIR/simple_model_rocket.ork"

# Clear out any existing task artifacts
rm -f "$ROCKETS_DIR/payload_lofter.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/expansion_report.txt" 2>/dev/null || true

# Record ground truth
echo "task_start_ts=$(date +%s)" > /tmp/task_start_time.txt

# Launch OpenRocket
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

launch_openrocket "$ROCKETS_DIR/simple_model_rocket.ork"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

take_screenshot /tmp/task_initial.png 2>/dev/null || true
echo "=== Task setup complete ==="
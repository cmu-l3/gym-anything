#!/bin/bash
set -e
echo "=== Setting up apply_chamfer task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Kill any running FreeCAD instance
kill_freecad

# 2. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 3. Prepare the workspace
DOCS_DIR="/home/ga/Documents/FreeCAD"
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# 4. Clean up previous results to ensure we detect new work
rm -f "$DOCS_DIR/chamfered_blocks.FCStd"
rm -f "$DOCS_DIR/chamfered_topbox.step"

# 5. Ensure the input file exists
# We prefer the fresh copy from /opt/freecad_samples/ if available
if [ -f "/opt/freecad_samples/contact_blocks.FCStd" ]; then
    cp "/opt/freecad_samples/contact_blocks.FCStd" "$DOCS_DIR/contact_blocks.FCStd"
elif [ ! -f "$DOCS_DIR/contact_blocks.FCStd" ]; then
    # Fallback if neither exists (should not happen in correct env)
    echo "ERROR: contact_blocks.FCStd not found!"
    exit 1
fi

# Set permissions
chown ga:ga "$DOCS_DIR/contact_blocks.FCStd"

# 6. Launch FreeCAD (Empty state as per description)
# The description says: "Open the FreeCAD file..." implying agent does it.
# So we start FreeCAD with an empty document or Start page suppressed.
echo "Starting FreeCAD..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority freecad > /tmp/freecad_task.log 2>&1 &"

# 7. Wait for window
wait_for_freecad 30

# 8. Maximize window
maximize_freecad

# 9. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
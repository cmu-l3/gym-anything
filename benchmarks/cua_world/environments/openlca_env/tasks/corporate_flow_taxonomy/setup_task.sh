#!/bin/bash
# Setup script for Corporate Flow Taxonomy task
# Ensures clean state: removes specific database if it exists, launches OpenLCA

source /workspace/scripts/task_utils.sh

echo "=== Setting up Corporate Flow Taxonomy task ==="

# 1. Clean up any previous run artifacts
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/db_flow_names.txt 2>/dev/null || true

# 2. Ensure the target database does NOT exist (clean slate)
TARGET_DB_DIR="/home/ga/openLCA-data-1.4/databases/ChemCorp_LCA"
if [ -d "$TARGET_DB_DIR" ]; then
    echo "Removing pre-existing ChemCorp_LCA database..."
    rm -rf "$TARGET_DB_DIR"
fi

# 3. Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# 4. Launch OpenLCA
# We launch it so the agent lands on the welcome/navigation screen ready to create a DB
echo "Launching OpenLCA..."
launch_openlca 180

# 5. Configure window
sleep 5
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
    echo "OpenLCA window maximized"
fi

# 6. Capture initial state screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="
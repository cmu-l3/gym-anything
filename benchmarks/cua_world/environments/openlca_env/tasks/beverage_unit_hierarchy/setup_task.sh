#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Beverage Unit Hierarchy task ==="

# Clean up previous artifacts
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/derby_*.txt 2>/dev/null || true

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure USLCI database exists (or is imported) so the user has a playground
# We don't strictly NEED USLCI for this task (it's custom units), but 
# creating a unit group requires an active database.
echo "Ensuring database availability..."
DB_DIR="/home/ga/openLCA-data-1.4/databases"
mkdir -p "$DB_DIR"
chown ga:ga "$DB_DIR"

# Check if any database exists
DB_COUNT=$(count_openlca_databases)
if [ "$DB_COUNT" -eq 0 ]; then
    echo "No databases found. Preparing USLCI for import..."
    # We won't force import here to save setup time, but we ensure the zip is ready
    # The agent might need to create a "Sandbox" database.
    # Actually, to reduce friction, let's try to provide an empty database if possible.
    # Since we can't easily create a Derby DB from bash, we rely on the agent 
    # OR we assume the environment might have one.
    # We will just ensure the import file is ready if they want to use it.
    USLCI_ZIP="/home/ga/LCA_Imports/uslci_database.zip"
    if [ ! -f "$USLCI_ZIP" ] && [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        mkdir -p "/home/ga/LCA_Imports"
        cp /opt/openlca_data/uslci_database.zip "$USLCI_ZIP"
        chown ga:ga "$USLCI_ZIP"
    fi
else
    echo "Database(s) found: $DB_COUNT"
fi

# Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# Maximize window
sleep 2
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
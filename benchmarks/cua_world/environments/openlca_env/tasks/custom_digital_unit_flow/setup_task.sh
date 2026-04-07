#!/bin/bash
# Setup script for Custom Digital Unit Flow task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Custom Digital Unit Flow task ==="

# Clean up previous results
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/digital_units_query.txt 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure an active database exists
# The task requires modifying database ontology (Units/Properties), so a DB must be open.
# We check for USLCI, if not present we let the agent know (or create an empty one).
# In this environment, USLCI is usually available to import.
# For ontology tasks, an empty database is actually fine/cleaner, but USLCI is standard.

DB_DIR="/home/ga/openLCA-data-1.4/databases"
mkdir -p "$DB_DIR"
chown ga:ga "$DB_DIR"

# Check if any database exists
DB_COUNT=$(count_openlca_databases)
echo "Initial database count: $DB_COUNT"

if [ "$DB_COUNT" -eq 0 ]; then
    echo "No databases found. Agent will need to create one."
else
    echo "Existing databases found. Agent can use existing or create new."
fi

# Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# Configure window
sleep 2
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
    echo "OpenLCA window maximized"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="
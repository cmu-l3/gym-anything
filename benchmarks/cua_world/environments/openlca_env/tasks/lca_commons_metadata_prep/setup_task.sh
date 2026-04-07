#!/bin/bash
# setup_task.sh for lca_commons_metadata_prep

source /workspace/scripts/task_utils.sh

echo "=== Setting up LCA Commons Metadata Prep task ==="

# 1. Clean up previous results
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/initial_db_state.txt 2>/dev/null || true

# 2. Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# 3. Ensure we have a database to work in
# If USLCI exists, we use it. If not, we create an empty one or let the agent do it.
# To ensure a smooth start, we'll launch OpenLCA. 
# The agent is expected to work in *any* open database.
# If no database exists, the agent will have to create one (which is fine, but we prefer a ready state).

DB_DIR="/home/ga/openLCA-data-1.4/databases"
mkdir -p "$DB_DIR"
chown ga:ga "$DB_DIR"

# Check if any database exists
DB_COUNT=$(count_openlca_databases 2>/dev/null || echo "0")
if [ "$DB_COUNT" -eq 0 ]; then
    echo "No databases found. Agent will need to create one."
else
    echo "Found $DB_COUNT existing databases."
fi

# 4. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 5. Maximize window
sleep 5
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# 6. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
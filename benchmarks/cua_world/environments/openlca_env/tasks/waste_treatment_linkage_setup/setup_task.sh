#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Waste Treatment Linkage Task ==="

# 1. Clean previous state
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/db_queries.txt 2>/dev/null || true

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Ensure a working database exists
# We need a database to create things in. If USLCI exists, good.
# If not, create an empty one named "Waste_Model_DB" to ensure the agent has a playground.
# However, creating a DB via script is hard without UI interaction in OpenLCA.
# We will rely on the agent to pick an existing DB or create one (Task description implies creation in OpenLCA).
# To be safe, we ensure USLCI is available if they want to use it, but they can create their own.
ensure_uslci_database > /dev/null

# 4. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 5. Window management
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# 6. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
#!/bin/bash
# Setup script for Regionalized Location Tagging task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Regionalized Location Tagging task ==="

# 1. Clean up previous artifacts
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/location_mapping.csv 2>/dev/null || true
mkdir -p /home/ga/LCA_Results
chown ga:ga /home/ga/LCA_Results

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Ensure USLCI database zip is available for import
# (Agent is expected to import it if not present, but we make sure the source exists)
USLCI_SOURCE="/home/ga/LCA_Imports/uslci_database.zip"
if [ ! -f "$USLCI_SOURCE" ]; then
    echo "Restoring USLCI database source..."
    mkdir -p /home/ga/LCA_Imports
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        cp "/opt/openlca_data/uslci_database.zip" "$USLCI_SOURCE"
        chown -R ga:ga /home/ga/LCA_Imports
    fi
fi

# 4. Record initial database state (to check if they modified it)
# Find active database if any
DB_DIR="/home/ga/openLCA-data-1.4/databases"
INITIAL_LOC_COUNT=0
ACTIVE_DB=""

# Try to find an existing USLCI db to get baseline counts
for db_path in "$DB_DIR"/*/; do
    db_name=$(basename "$db_path" 2>/dev/null)
    if echo "$db_name" | grep -qi "uslci\|lci"; then
        ACTIVE_DB="$db_path"
        break
    fi
done

if [ -n "$ACTIVE_DB" ]; then
    # OpenLCA uses Derby; we can query TBL_LOCATIONS if openLCA isn't locking it strictly
    # (Note: querying while running might be tricky, but usually read-only works or we do it before launch)
    INITIAL_LOC_COUNT=$(derby_count "$ACTIVE_DB" "LOCATIONS" 2>/dev/null || echo "0")
fi
echo "$INITIAL_LOC_COUNT" > /tmp/initial_loc_count.txt

# 5. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 6. Maximize window
sleep 2
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
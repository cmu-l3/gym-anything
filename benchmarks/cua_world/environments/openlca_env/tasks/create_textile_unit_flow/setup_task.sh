#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Textile Unit Flow task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Ensure USLCI database exists (we need a DB to create objects in)
# ============================================================
DB_DIR="/home/ga/openLCA-data-1.4/databases"
USLCI_DB=$(ensure_uslci_database)

if [ -z "$USLCI_DB" ]; then
    echo "No USLCI database found. Creating a blank database for the agent..."
    # If no USLCI, we can't easily create a blank one programmatically without the GUI or heavy Java API usage.
    # However, for this task, we can just let the agent create one if needed, 
    # but to ensure a clean start, we'll try to provide the USLCI import file.
    # Ideally, we want the agent to focus on the unit creation, not DB import.
    # So we will try to prepare a basic DB if possible, or just rely on the existing USLCI import logic.
    echo "Ensuring USLCI import file is available..."
    if [ ! -f "/home/ga/LCA_Imports/uslci_database.zip" ] && [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        mkdir -p "/home/ga/LCA_Imports"
        cp "/opt/openlca_data/uslci_database.zip" "/home/ga/LCA_Imports/"
        chown ga:ga "/home/ga/LCA_Imports/uslci_database.zip"
    fi
else
    echo "Found active database: $(basename "$USLCI_DB")"
fi

# ============================================================
# 2. Record Initial Database State
# ============================================================
# We want to know how many unit groups, flows, etc. exist before the task
# so we can verify NEW ones were created.

echo "Recording initial database counts..."
ACTIVE_DB=""
# Pick the largest database directory
for db_path in "$DB_DIR"/*/; do
    if [ -d "$db_path" ]; then
        ACTIVE_DB="$db_path"
        break
    fi
done

if [ -n "$ACTIVE_DB" ]; then
    # We need to query Derby while OpenLCA is NOT running, or use a non-locking query if possible.
    # Since OpenLCA isn't launched yet, we can query safely.
    
    # Store counts in a temp file
    UG_COUNT=$(derby_count "$ACTIVE_DB" "UNIT_GROUPS")
    FP_COUNT=$(derby_count "$ACTIVE_DB" "FLOW_PROPERTIES")
    FLOW_COUNT=$(derby_count "$ACTIVE_DB" "FLOWS")
    
    echo "{\"ug\": $UG_COUNT, \"fp\": $FP_COUNT, \"flow\": $FLOW_COUNT}" > /tmp/initial_counts.json
    echo "Initial counts: UG=$UG_COUNT, FP=$FP_COUNT, FLOW=$FLOW_COUNT"
else
    echo "{\"ug\": 0, \"fp\": 0, \"flow\": 0}" > /tmp/initial_counts.json
fi

# ============================================================
# 3. Launch OpenLCA
# ============================================================
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
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
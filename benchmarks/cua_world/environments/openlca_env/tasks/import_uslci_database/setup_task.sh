#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Import USLCI Database task ==="

# ============================================================
# Clean up any state from previous task runs
# ============================================================
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/initial_db_count 2>/dev/null || true

# Record initial state (for detecting changes)
DB_DIR="/home/ga/openLCA-data-1.4/databases"
mkdir -p "$DB_DIR"
chown ga:ga "$DB_DIR"

# Count existing databases BEFORE task starts
INITIAL_DB_COUNT=$(ls -1d "$DB_DIR"/*/ 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_DB_COUNT" > /tmp/initial_db_count
echo "Initial database count: $INITIAL_DB_COUNT"

# List existing databases
echo "Existing databases:"
ls -la "$DB_DIR/" 2>/dev/null || echo "No databases yet"

# Ensure USLCI import file exists
IMPORT_FILE="/home/ga/LCA_Imports/uslci_database.zip"
if [ ! -f "$IMPORT_FILE" ]; then
    echo "Warning: USLCI database not found at $IMPORT_FILE"
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        cp /opt/openlca_data/uslci_database.zip "$IMPORT_FILE"
        chown ga:ga "$IMPORT_FILE"
        echo "Copied USLCI database from /opt/openlca_data/"
    fi
fi

echo ""
echo "Available import files:"
ls -la /home/ga/LCA_Imports/ 2>/dev/null || echo "No import files found"

# ============================================================
# Launch OpenLCA (but do NOT create database or import data!)
# ============================================================

echo ""
echo "Launching OpenLCA..."
launch_openlca 180

# Maximize the OpenLCA window
sleep 2
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
    echo "OpenLCA window maximized"
fi

# Take initial screenshot to record starting state
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Task setup complete ==="

#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Product System task ==="

# ============================================================
# SELF-CONTAINED SETUP: Ensure prerequisites are met
# If USLCI database doesn't exist, create and import it
# ============================================================

# Clean up any previous state
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/initial_product_systems 2>/dev/null || true

DB_DIR="/home/ga/openLCA-data-1.4/databases"
mkdir -p "$DB_DIR"
chown ga:ga "$DB_DIR"

# Check for existing USLCI database
USLCI_DB=$(ensure_uslci_database)

if [ -z "$USLCI_DB" ]; then
    echo "No USLCI database found. Agent will need to create and import first."
else
    echo "Found USLCI database: $(basename "$USLCI_DB") ($(du -sh "$USLCI_DB" 2>/dev/null | cut -f1))"
fi

# Record initial state for detecting product system creation
echo "0" > /tmp/initial_product_systems

# ============================================================
# Launch OpenLCA
# ============================================================

echo ""
echo "Launching OpenLCA..."
launch_openlca 180

# Maximize window
sleep 2
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
    echo "OpenLCA window maximized"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Task setup complete ==="
